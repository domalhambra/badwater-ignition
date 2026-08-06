import Foundation

/// A minimal **STORE-only** (uncompressed, method 0) ZIP writer — just enough to
/// package an XLSX (OOXML) workbook with no third-party dependency and no
/// Compression framework (keeping the core Linux-testable). Deterministic: a
/// fixed DOS timestamp means identical input yields byte-identical output.
///
/// STORE triples the size of a compressible payload, which is irrelevant for a
/// few kilobytes of spreadsheet XML shared over the OS share sheet; do not reuse
/// this for large binary parts.
public enum ZipArchive {

    /// Limits of the classic (non-Zip64) format this writer emits. A ZIP header
    /// stores a name length in 16 bits and a size/offset in 32, so exceeding
    /// either can't be represented — and the conversions below would *trap*
    /// rather than fail. Both are far beyond a spreadsheet of shift
    /// observations; they exist so a future caller gets a diagnosable error
    /// instead of a crash on a fireline.
    public enum Limit {
        public static let maxEntryNameBytes = Int(UInt16.max)
        public static let maxEntryBytes = Int(UInt32.max)
        public static let maxEntryCount = Int(UInt16.max)
        /// The whole archive, not just each entry: central-directory offsets are
        /// 32-bit too, so two individually-legal entries can still push the
        /// later offsets past what the format can encode.
        public static let maxArchiveBytes = Int(UInt32.max)
    }

    /// Why a ZIP could not be written.
    public enum Failure: Error, Equatable {
        case entryNameTooLong(path: String, bytes: Int)
        case entryTooLarge(path: String, bytes: Int)
        case tooManyEntries(count: Int)
        case archiveTooLarge(bytes: Int)
    }

    /// Package entries (path → bytes) into a ZIP container.
    ///
    /// Preconditions are checked rather than trusted: see ``Limit``. Use
    /// ``zipChecked(_:)`` to handle a violation instead of trapping.
    public static func zip(_ entries: [(path: String, data: Data)]) -> Data {
        // The archive this app builds is a few kilobytes of sheet XML with short
        // fixed paths, so a violation here is a programming error, not a runtime
        // condition — hence the trap, with a message that says which entry.
        do {
            return try zipChecked(entries)
        } catch {
            preconditionFailure("ZipArchive.zip: \(error)")
        }
    }

    /// Package entries into a ZIP container, throwing rather than trapping when
    /// an entry exceeds what the classic ZIP format can encode.
    public static func zipChecked(_ entries: [(path: String, data: Data)]) throws -> Data {
        guard entries.count <= Limit.maxEntryCount else {
            throw Failure.tooManyEntries(count: entries.count)
        }
        for entry in entries {
            let nameBytes = entry.path.utf8.count
            guard nameBytes <= Limit.maxEntryNameBytes else {
                throw Failure.entryNameTooLong(path: entry.path, bytes: nameBytes)
            }
            guard entry.data.count <= Limit.maxEntryBytes else {
                throw Failure.entryTooLarge(path: entry.path, bytes: entry.data.count)
            }
        }
        // Per-entry checks alone don't deliver the no-trap contract: `build`
        // converts each running offset to UInt32, and entries that pass
        // individually can sum past 4 GiB. Sum the exact layout up front —
        // per entry a 30-byte local header + name + data, a 46-byte central
        // header + name, then the 22-byte end record. (Int is 64-bit on every
        // supported platform, so this sum itself cannot overflow within the
        // per-entry and count limits above.)
        var total = 22
        for entry in entries {
            let nameBytes = entry.path.utf8.count
            total += 30 + nameBytes + entry.data.count
            total += 46 + nameBytes
        }
        guard total <= Limit.maxArchiveBytes else {
            throw Failure.archiveTooLarge(bytes: total)
        }
        return build(entries)
    }

    private static func build(_ entries: [(path: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        let dosTime: UInt16 = 0x0000
        let dosDate: UInt16 = 0x0021   // 1980-01-01, fixed for determinism

        func put(_ d: inout Data, _ bytes: [UInt8]) { d.append(contentsOf: bytes) }

        for entry in entries {
            let name = Array(entry.path.utf8)
            let bytes = [UInt8](entry.data)
            let crc = CRC32.checksum(bytes)
            let size = UInt32(bytes.count)
            let offset = UInt32(out.count)

            // Local file header
            put(&out, le32(0x0403_4b50))
            put(&out, le16(20)); put(&out, le16(0)); put(&out, le16(0))   // version, flags, method(store)
            put(&out, le16(dosTime)); put(&out, le16(dosDate))
            put(&out, le32(crc)); put(&out, le32(size)); put(&out, le32(size))
            put(&out, le16(UInt16(name.count))); put(&out, le16(0))       // name len, extra len
            put(&out, name)
            put(&out, bytes)

            // Central directory header
            put(&central, le32(0x0201_4b50))
            put(&central, le16(20)); put(&central, le16(20))              // version made by / needed
            put(&central, le16(0)); put(&central, le16(0))                // flags, method(store)
            put(&central, le16(dosTime)); put(&central, le16(dosDate))
            put(&central, le32(crc)); put(&central, le32(size)); put(&central, le32(size))
            put(&central, le16(UInt16(name.count)))
            put(&central, le16(0)); put(&central, le16(0)); put(&central, le16(0)); put(&central, le16(0)) // extra, comment, disk, int attr
            put(&central, le32(0)); put(&central, le32(offset))           // ext attr, local header offset
            put(&central, name)
        }

        let cdOffset = UInt32(out.count)
        let cdSize = UInt32(central.count)
        out.append(central)

        // End of central directory
        put(&out, le32(0x0605_4b50))
        put(&out, le16(0)); put(&out, le16(0))
        put(&out, le16(UInt16(entries.count))); put(&out, le16(UInt16(entries.count)))
        put(&out, le32(cdSize)); put(&out, le32(cdOffset)); put(&out, le16(0))
        return out
    }

    private static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }
    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }
}

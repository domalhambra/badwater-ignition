import Foundation

/// CRC-32 (IEEE, reflected, polynomial `0xEDB88320`) — the checksum every ZIP
/// entry needs. Pure and Linux-testable; golden-tested against known vectors.
public enum CRC32 {
    /// Precomputed lookup table.
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    /// The CRC-32 checksum of a byte sequence.
    public static func checksum<S: Sequence>(_ bytes: S) -> UInt32 where S.Element == UInt8 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}

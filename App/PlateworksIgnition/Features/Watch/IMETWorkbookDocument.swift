import SwiftUI
import UniformTypeIdentifiers

/// A minimal `FileDocument` wrapper so the IMET `.xlsx` workbook bytes
/// (`WeatherWatchModel.imetWorkbookData()`) can be handed to the cross-platform
/// `.fileExporter` sheet on both iOS and macOS.
struct IMETWorkbookDocument: FileDocument {
    /// `.xlsx`, falling back to plain data if the system can't resolve the type.
    static let xlsx: UTType = UTType(filenameExtension: "xlsx", conformingTo: .spreadsheet) ?? .data
    static var readableContentTypes: [UTType] { [xlsx] }
    static var writableContentTypes: [UTType] { [xlsx] }

    var data: Data
    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The community identifier for markdown that editors on macOS share, and
    /// the one mdview declares in its Info.plist.
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}

/// One opened markdown file. `DocumentGroup` creates a separate instance — and
/// therefore a separate window — per file, which is what gives each document
/// its own scroll position and title.
///
/// Read-only by design: mdview never writes, so `fileWrapper(configuration:)`
/// is unreachable through a viewing-only `DocumentGroup`.
struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdown, .plainText] }
    static var writableContentTypes: [UTType] { [] }

    let text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = try TextDecoder.decode(data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.featureUnsupported)
    }
}

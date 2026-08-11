import Foundation

/// Turns the raw bytes of a markdown file into text.
///
/// Decoding is done from `Data` rather than a `URL` so it can run inside a
/// `FileDocument`, and byte-order marks are handled explicitly rather than
/// left to Foundation, whose behaviour differs between OS releases.
enum TextDecoder {
    /// Parsing and highlighting run synchronously on the main thread, which is
    /// imperceptible for ordinary documents but would stall the UI on a
    /// pathologically large one, so refuse those outright with a clear reason.
    static let maximumFileSize = 32 * 1024 * 1024

    static func decode(_ data: Data) throws -> String {
        guard data.count <= maximumFileSize else {
            throw CocoaError(
                .fileReadTooLarge,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "the file is larger than \(maximumFileSize / (1024 * 1024)) MB."
                ]
            )
        }

        if let encoding = encodingFromByteOrderMark(data),
           let text = String(data: data, encoding: encoding) {
            return strippingByteOrderMark(text)
        }
        // Almost all markdown is UTF-8; this also covers plain ASCII.
        if let utf8 = String(data: data, encoding: .utf8) {
            return strippingByteOrderMark(utf8)
        }
        for encoding in candidateEncodings(for: data) {
            if let text = String(data: data, encoding: encoding) {
                return strippingByteOrderMark(text)
            }
        }
        throw CocoaError(.fileReadUnknownStringEncoding)
    }

    static func encodingFromByteOrderMark(_ data: Data) -> String.Encoding? {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { return .utf8 }
        if data.starts(with: [0xFF, 0xFE]) { return .utf16LittleEndian }
        if data.starts(with: [0xFE, 0xFF]) { return .utf16BigEndian }
        return nil
    }

    /// Whether a decoded byte-order mark survives as a leading U+FEFF depends
    /// on the OS version, so normalise it away: it is invisible, is not part
    /// of the document, and would otherwise sit in front of the first heading
    /// marker.
    static func strippingByteOrderMark(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    /// UTF-16 without a byte-order mark is not self-describing, and Latin-1
    /// happily "decodes" it into text riddled with NUL characters, so sniff
    /// for it explicitly before falling back to a single-byte encoding.
    static func candidateEncodings(for data: Data) -> [String.Encoding] {
        var candidates: [String.Encoding] = []

        if data.count >= 2, data.count.isMultiple(of: 2) {
            var nulsAtEvenOffsets = 0
            var nulsAtOddOffsets = 0
            for (offset, byte) in data.prefix(512).enumerated() where byte == 0 {
                if offset.isMultiple(of: 2) { nulsAtEvenOffsets += 1 } else { nulsAtOddOffsets += 1 }
            }
            // ASCII-range text in UTF-16BE puts its NUL byte first ("\0#"),
            // and in UTF-16LE second ("#\0").
            if nulsAtEvenOffsets > nulsAtOddOffsets {
                candidates.append(.utf16BigEndian)
            } else if nulsAtOddOffsets > 0 {
                candidates.append(.utf16LittleEndian)
            }
        }

        candidates.append(.isoLatin1) // last resort: decodes any byte sequence
        return candidates
    }
}

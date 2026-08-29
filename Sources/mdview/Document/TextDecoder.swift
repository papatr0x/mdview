import Foundation

/// Turns the raw bytes of a markdown file into text.
///
/// Decoding is done from `Data` rather than a `URL` so it can run inside a
/// `FileDocument`, and byte-order marks are handled explicitly rather than
/// left to Foundation, whose behaviour differs between OS releases.
enum TextDecoder {
    /// An upper bound on garbage input — not a promise about responsiveness.
    ///
    /// Parsing and highlighting run synchronously on the main thread at
    /// roughly half a second per megabyte (measured), so a file anywhere near
    /// this ceiling *does* stall the UI for seconds. That is accepted rather
    /// than papered over with a smaller number: real markdown is orders of
    /// magnitude smaller, and the point of the limit is to reject something
    /// that is not a document at all, with a clear reason instead of a hang.
    /// Making large files genuinely comfortable is a rendering change — cache
    /// the parsed tree and re-apply only attributes — not a lower ceiling.
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
        // Sniffed before UTF-8 is attempted, not after it fails: ASCII text in
        // UTF-16 is *valid* UTF-8. Every byte of it — the interleaved NULs
        // included — is under 0x80, so UTF-8 accepts the file and hands back
        // the text with a NUL between every character, and the sniffer below
        // never runs. Non-ASCII text hid this: its high bytes are invalid
        // UTF-8, so those files did reach the sniffer and decoded correctly.
        if let utf16 = utf16EncodingWithoutByteOrderMark(for: data),
           let text = String(data: data, encoding: utf16) {
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

    /// UTF-16 without a byte-order mark is not self-describing, so sniff for
    /// it by the NUL bytes that ASCII-range characters leave behind: in
    /// UTF-16BE the NUL comes first ("\0#"), in UTF-16LE second ("#\0").
    ///
    /// Deliberately demanding, because this answer preempts UTF-8: a UTF-8
    /// document with a stray NUL in it must not be mistaken for UTF-16. Real
    /// UTF-16 prose is about half NUL bytes, so requiring a quarter of the
    /// sample is far more than an accident could produce and far less than the
    /// genuine article carries.
    static func utf16EncodingWithoutByteOrderMark(for data: Data) -> String.Encoding? {
        guard data.count >= 2, data.count.isMultiple(of: 2) else { return nil }

        let sample = data.prefix(512)
        var nulsAtEvenOffsets = 0
        var nulsAtOddOffsets = 0
        for (offset, byte) in sample.enumerated() where byte == 0 {
            if offset.isMultiple(of: 2) { nulsAtEvenOffsets += 1 } else { nulsAtOddOffsets += 1 }
        }

        let threshold = sample.count / 4
        if nulsAtEvenOffsets > nulsAtOddOffsets, nulsAtEvenOffsets >= threshold {
            return .utf16BigEndian
        }
        if nulsAtOddOffsets > nulsAtEvenOffsets, nulsAtOddOffsets >= threshold {
            return .utf16LittleEndian
        }
        return nil
    }

    /// The last resort, reached only once a byte-order mark, the UTF-16 sniff,
    /// and UTF-8 have all failed to produce text. Latin-1 decodes any byte
    /// sequence at all, so it ends the chain rather than throwing.
    static func candidateEncodings(for data: Data) -> [String.Encoding] {
        var candidates: [String.Encoding] = []
        if let utf16 = utf16EncodingWithoutByteOrderMark(for: data) {
            candidates.append(utf16)
        }
        candidates.append(.isoLatin1)
        return candidates
    }
}

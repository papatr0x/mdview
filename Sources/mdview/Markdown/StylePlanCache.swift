import Foundation

/// Keeps one document's `StylePlan` alive so that changing a color or the font
/// size repaints without parsing the file again.
///
/// One instance per window: a document window shows a single, immutable text
/// for its lifetime, so the cache holds a single entry and the text is the
/// whole key. Comparing that key is cheap in the case that matters — the same
/// `String` instance is handed back on every render, which `==` settles by
/// identity before it looks at any characters.
final class StylePlanCache {
    private var cachedText: String?
    private var cachedPlan: StylePlan?

    func plan(for text: String) -> StylePlan {
        if let cachedPlan, cachedText == text {
            return cachedPlan
        }
        let plan = MarkdownRenderer.plan(for: text)
        cachedText = text
        cachedPlan = plan
        return plan
    }
}

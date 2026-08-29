import Foundation

/// Keeps one document's `StylePlan` alive so that changing a color or the font
/// size repaints without parsing the file again — and keeps the parse itself
/// off the main thread, so a window can come up before its document has been
/// highlighted.
///
/// One instance per window: a document window shows a single, immutable text
/// for its lifetime, so the cache holds a single entry and the text is the
/// whole key. Comparing that key is cheap in the case that matters — the same
/// `String` instance is handed back on every render, which `==` settles by
/// identity before it looks at any characters.
///
/// Main-actor isolated on purpose. The parse runs on a detached task, but
/// everything it touches here is read and written from the main actor, so the
/// background half owns nothing and races with nothing.
@MainActor
final class StylePlanCache {
    private var cachedText: String?
    private var cachedPlan: StylePlan?
    private var pendingText: String?
    private var pending: Task<StylePlan, Never>?

    /// The plan if it is already known, without waiting for anything.
    ///
    /// This is the path every preference change takes and it has to stay
    /// synchronous: the color wells are continuous, so a drag repaints once per
    /// mouse event, and deferring a plan that is already in hand would put a
    /// frame of lag into that.
    func cachedPlan(for text: String) -> StylePlan? {
        cachedText == text ? cachedPlan : nil
    }

    /// Parses off the main thread, or joins the parse already running for this
    /// text instead of starting a second one — a settings change arriving
    /// mid-parse must not redo the work, only repaint once it lands.
    func plan(for text: String) async -> StylePlan {
        if let plan = cachedPlan(for: text) { return plan }

        let task: Task<StylePlan, Never>
        if pendingText == text, let pending {
            task = pending
        } else {
            task = Task.detached(priority: .userInitiated) {
                MarkdownRenderer.plan(for: text)
            }
            pendingText = text
            pending = task
        }

        let plan = await task.value

        // A different text may have been asked for while this one parsed, in
        // which case that parse owns the cache and this result is only returned
        // to its own caller.
        if pendingText == text {
            cachedText = text
            cachedPlan = plan
            pendingText = nil
            pending = nil
        }
        return plan
    }
}

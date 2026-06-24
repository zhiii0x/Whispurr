import Foundation

/// Rewrites a raw transcript into clean text. Implementations must NEVER throw —
/// degrade to returning the input unchanged so a cycle always inserts text.
@MainActor public protocol TextCleanup: AnyObject {
    func clean(_ text: String) async -> String

    /// Streaming variant: same final result, but reports the cumulative cleaned
    /// text as it is generated (for live HUD display). Has a default that simply
    /// forwards to `clean(_:)` with no intermediate updates, so existing
    /// implementations (and test fakes) need no changes.
    func clean(_ text: String, onPartial: @escaping (String) -> Void) async -> String
}

public extension TextCleanup {
    func clean(_ text: String, onPartial: @escaping (String) -> Void) async -> String {
        await clean(text)
    }
}

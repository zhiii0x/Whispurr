import Foundation

/// The latency-coupled timeouts that together bound end-of-utterance delay.
/// Grouped here (with the note that they SUM into perceived latency) so they can
/// be reasoned about and tuned in one place rather than scattered across files.
public enum Timeouts {
    /// Watchdog for draining the recognizer after key-up (worst case only —
    /// the normal path returns as soon as results settle).
    public static let finalizeDrain: Duration = .seconds(3)
    /// Watchdog for the on-device cleanup LLM (worst case only).
    public static let cleanupWatchdog: Duration = .seconds(6)
    /// How long the `.error` badge lingers before auto-resetting to idle.
    public static let errorReset: Duration = .seconds(3)
    /// Settle delay before restoring the clipboard after a synthetic ⌘V.
    public static let pasteSettle: Duration = .milliseconds(150)
}

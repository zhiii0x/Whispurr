import Foundation

/// Drives speech capture + recognition behind a fakeable seam. A concrete
/// engine owns its own audio. Callbacks are delivered on the main actor.
@MainActor public protocol TranscriptionEngine: AnyObject {
    /// Begin capturing and transcribing. `onPartial` streams volatile previews;
    /// `onFinal` delivers each finalized segment (may be called multiple times).
    func start(onPartial: @escaping (String) -> Void,
               onFinal: @escaping (String) -> Void) async throws
    /// Same, plus `onFailure` for a failure that happens *after* `start` returned
    /// (e.g. the recognizer dies mid-utterance), so it can be surfaced instead of
    /// silently going deaf. Has a default that forwards to the two-callback form
    /// and never reports, so simple engines (and test fakes) need no changes.
    func start(onPartial: @escaping (String) -> Void,
               onFinal: @escaping (String) -> Void,
               onFailure: @escaping (Error) -> Void) async throws
    /// Stop capture and flush the trailing phrase; returns once the final
    /// segment has been delivered via `onFinal`.
    func stopAndFinalize() async throws
    /// Abort immediately without finalizing.
    func cancel()
}

public extension TranscriptionEngine {
    func start(onPartial: @escaping (String) -> Void,
               onFinal: @escaping (String) -> Void,
               onFailure: @escaping (Error) -> Void) async throws {
        try await start(onPartial: onPartial, onFinal: onFinal)
    }
}

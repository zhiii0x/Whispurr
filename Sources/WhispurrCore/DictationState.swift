import Foundation

/// The single source-of-truth phase of a dictation session.
public enum DictationState: Equatable, Sendable {
    case idle
    case listening
    case processing
    case error(String)
}

/// Things that can happen to move between states.
public enum DictationEvent: Equatable, Sendable {
    case pushToTalkDown
    case pushToTalkUp
    case transcriptionFinished
    case cancel              // user aborted (Esc) — discard, insert nothing
    case failed(String)
    case reset
}

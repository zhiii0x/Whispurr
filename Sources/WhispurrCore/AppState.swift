import Foundation

/// Holds the current dictation state and notifies a single observer on change.
/// (A closure keeps this AppKit-free so it stays unit-testable; the app layer
/// wires `onChange` to the cat animator.)
@MainActor public final class AppState {
    public private(set) var state: DictationState = .idle
    public var onChange: ((DictationState) -> Void)?

    public init() {}

    public func set(_ newState: DictationState) {
        state = newState
        onChange?(newState)
    }
}

import Foundation

/// Maps `DictationEvent`s onto `DictationState` transitions.
/// Invalid transitions leave the state unchanged.
public struct DictationStateMachine: Sendable {
    public private(set) var state: DictationState

    public init(state: DictationState = .idle) {
        self.state = state
    }

    @discardableResult
    public mutating func handle(_ event: DictationEvent) -> DictationState {
        switch (state, event) {
        case (.idle, .pushToTalkDown):
            state = .listening
        case (.listening, .pushToTalkUp):
            state = .processing
        case (.processing, .transcriptionFinished):
            state = .idle
        case (.listening, .cancel), (.processing, .cancel):
            state = .idle
        case (_, .failed(let message)):
            state = .error(message)
        case (_, .reset):
            state = .idle
        default:
            break // ignore invalid transitions
        }
        return state
    }
}

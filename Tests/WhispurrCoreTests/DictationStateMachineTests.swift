import XCTest
@testable import WhispurrCore

final class DictationStateMachineTests: XCTestCase {
    func testPushToTalkDownStartsListening() {
        var m = DictationStateMachine()
        XCTAssertEqual(m.handle(.pushToTalkDown), .listening)
    }

    func testReleaseGoesToProcessing() {
        var m = DictationStateMachine(state: .listening)
        XCTAssertEqual(m.handle(.pushToTalkUp), .processing)
    }

    func testFinishReturnsToIdle() {
        var m = DictationStateMachine(state: .processing)
        XCTAssertEqual(m.handle(.transcriptionFinished), .idle)
    }

    func testFailureGoesToError() {
        var m = DictationStateMachine(state: .listening)
        XCTAssertEqual(m.handle(.failed("mic denied")), .error("mic denied"))
    }

    func testResetFromError() {
        var m = DictationStateMachine(state: .error("x"))
        XCTAssertEqual(m.handle(.reset), .idle)
    }

    func testInvalidTransitionIsIgnored() {
        var m = DictationStateMachine(state: .idle)
        // releasing the key while idle should do nothing
        XCTAssertEqual(m.handle(.pushToTalkUp), .idle)
    }
}

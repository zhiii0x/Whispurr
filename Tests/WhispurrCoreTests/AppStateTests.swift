import XCTest
@testable import WhispurrCore

@MainActor final class AppStateTests: XCTestCase {
    func testSettingStateNotifiesObserver() {
        let appState = AppState()
        var received: DictationState?
        appState.onChange = { received = $0 }

        appState.set(.listening)

        XCTAssertEqual(received, .listening)
        XCTAssertEqual(appState.state, .listening)
    }

    func testStartsIdle() {
        XCTAssertEqual(AppState().state, .idle)
    }
}

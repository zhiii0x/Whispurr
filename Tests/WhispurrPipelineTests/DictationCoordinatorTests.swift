import XCTest
import WhispurrCore
@testable import WhispurrPipeline

@MainActor
final class DictationCoordinatorTests: XCTestCase {
    /// No-op engine for tests that only care about state transitions.
    final class NoopEngine: TranscriptionEngine {
        func start(onPartial: @escaping (String) -> Void,
                   onFinal: @escaping (String) -> Void) async throws {}
        func stopAndFinalize() async throws {}
        func cancel() {}
    }

    private func makeCoordinator(_ app: AppState, _ hk: FakeHotkey) -> DictationCoordinator {
        DictationCoordinator(appState: app, hotkey: hk, engine: NoopEngine(),
                             cleanup: NoopCleanup(), inserter: NoopInserter())
    }

    func testPressStartsListening() {
        let app = AppState(); let hk = FakeHotkey()
        let c = makeCoordinator(app, hk)
        c.activate()
        hk.firePress()
        XCTAssertEqual(app.state, .listening)
    }

    func testReleaseGoesThroughProcessingToIdle() async {
        let app = AppState(); let hk = FakeHotkey()
        var seen: [DictationState] = []
        app.onChange = { seen.append($0) }
        let c = makeCoordinator(app, hk)
        c.activate()
        hk.firePress()
        seen.removeAll()
        hk.fireRelease()
        await c.waitForCycle()
        XCTAssertEqual(seen, [.processing, .idle])
        XCTAssertEqual(app.state, .idle)
    }

    func testPressIgnoredWhenNotIdle() {
        let app = AppState(); let hk = FakeHotkey()
        let c = makeCoordinator(app, hk)
        c.activate()
        hk.firePress()                 // -> listening
        hk.firePress()                 // ignored
        XCTAssertEqual(app.state, .listening)
    }

    func testReleaseIgnoredWhenNotListening() {
        let app = AppState(); let hk = FakeHotkey()
        let c = makeCoordinator(app, hk)
        c.activate()
        hk.fireRelease()               // ignored (idle)
        XCTAssertEqual(app.state, .idle)
    }
}

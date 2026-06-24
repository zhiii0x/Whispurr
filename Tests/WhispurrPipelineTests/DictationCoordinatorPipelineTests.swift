import XCTest
import WhispurrCore
@testable import WhispurrPipeline

@MainActor
final class DictationCoordinatorPipelineTests: XCTestCase {
    /// Fake engine: records start/stop, lets the test push finals.
    final class FakeEngine: TranscriptionEngine {
        private(set) var started = false
        private(set) var finalized = false
        private var onFinal: ((String) -> Void)?
        func start(onPartial: @escaping (String) -> Void,
                   onFinal: @escaping (String) -> Void) async throws {
            started = true; self.onFinal = onFinal
        }
        func stopAndFinalize() async throws { finalized = true }
        func cancel() {}
        func emitFinal(_ s: String) { onFinal?(s) }
    }

    private func makeCoordinator(_ app: AppState, _ hk: FakeHotkey, _ eng: FakeEngine) -> DictationCoordinator {
        DictationCoordinator(appState: app, hotkey: hk, engine: eng,
                             cleanup: NoopCleanup(), inserter: NoopInserter())
    }

    func testFullCycleProducesTranscriptAndReturnsToIdle() async {
        let app = AppState(); let hk = FakeHotkey(); let eng = FakeEngine()
        var states: [DictationState] = []; app.onChange = { states.append($0) }
        var transcript: String?
        let c = makeCoordinator(app, hk, eng)
        c.onTranscript = { transcript = $0 }
        c.activate()

        hk.firePress()
        await c.waitForStart()                 // test hook: awaits the start Task
        XCTAssertTrue(eng.started)
        XCTAssertEqual(app.state, .listening)

        eng.emitFinal("幫我 push 這個 commit")
        hk.fireRelease()
        await c.waitForCycle()                  // test hook: awaits the release Task

        XCTAssertTrue(eng.finalized)
        XCTAssertEqual(transcript, "幫我 push 這個 commit")   // Noop cleanup → unchanged
        XCTAssertEqual(app.state, .idle)
        XCTAssertEqual(states.suffix(2), [.processing, .idle])
    }

    func testEmptyTranscriptSkipsCallback() async {
        let app = AppState(); let hk = FakeHotkey(); let eng = FakeEngine()
        var called = false
        let c = makeCoordinator(app, hk, eng)
        c.onTranscript = { _ in called = true }
        c.activate()
        hk.firePress(); await c.waitForStart()
        hk.fireRelease(); await c.waitForCycle()
        XCTAssertFalse(called)                  // nothing said → no transcript
        XCTAssertEqual(app.state, .idle)
    }
}

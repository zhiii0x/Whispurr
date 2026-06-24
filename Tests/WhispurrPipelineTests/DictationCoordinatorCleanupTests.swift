import XCTest
import WhispurrCore
@testable import WhispurrPipeline

@MainActor
final class DictationCoordinatorCleanupTests: XCTestCase {
    final class FakeEngine: TranscriptionEngine {
        private var onFinal: ((String) -> Void)?
        func start(onPartial: @escaping (String) -> Void,
                   onFinal: @escaping (String) -> Void) async throws { self.onFinal = onFinal }
        func stopAndFinalize() async throws {}
        func cancel() {}
        func emitFinal(_ s: String) { onFinal?(s) }
    }
    final class FakeCleanup: TextCleanup {
        func clean(_ text: String) async -> String { "CLEAN(\(text))" }
    }
    final class FakeInserter: TextInserter {
        private(set) var inserted: [String] = []
        func insert(_ text: String) { inserted.append(text) }
    }

    func testCycleCleansThenInserts() async {
        let app = AppState(); let hk = FakeHotkey()
        let eng = FakeEngine(); let clean = FakeCleanup(); let ins = FakeInserter()
        let c = DictationCoordinator(appState: app, hotkey: hk, engine: eng,
                                     cleanup: clean, inserter: ins)
        var shown: String?
        c.onTranscript = { shown = $0 }
        c.activate()

        hk.firePress(); await c.waitForStart()
        eng.emitFinal("呃 我想做 cloud")
        hk.fireRelease(); await c.waitForCycle()

        XCTAssertEqual(ins.inserted, ["CLEAN(呃 我想做 cloud)"])
        XCTAssertEqual(shown, "CLEAN(呃 我想做 cloud)")   // menu shows the cleaned text
        XCTAssertEqual(app.state, .idle)
    }

    func testEmptyTranscriptInsertsNothing() async {
        let app = AppState(); let hk = FakeHotkey()
        let eng = FakeEngine(); let clean = FakeCleanup(); let ins = FakeInserter()
        let c = DictationCoordinator(appState: app, hotkey: hk, engine: eng,
                                     cleanup: clean, inserter: ins)
        c.activate()
        hk.firePress(); await c.waitForStart()
        hk.fireRelease(); await c.waitForCycle()
        XCTAssertTrue(ins.inserted.isEmpty)
        XCTAssertEqual(app.state, .idle)
    }
}

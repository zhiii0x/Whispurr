import XCTest
import WhispurrCore
@testable import WhispurrPipeline

@MainActor
final class DictationCoordinatorCancelTests: XCTestCase {
    final class FakeEngine: TranscriptionEngine {
        private(set) var cancelled = false
        private var onFinal: ((String) -> Void)?
        func start(onPartial: @escaping (String) -> Void,
                   onFinal: @escaping (String) -> Void) async throws { self.onFinal = onFinal }
        func stopAndFinalize() async throws {}
        func cancel() { cancelled = true }
        func emitFinal(_ s: String) { onFinal?(s) }
    }
    final class FakeInserter: TextInserter {
        private(set) var inserted: [String] = []
        func insert(_ text: String) { inserted.append(text) }
    }

    func testCancelDuringListeningDiscardsAndGoesIdle() async {
        let app = AppState(); let hk = FakeHotkey()
        let eng = FakeEngine(); let ins = FakeInserter()
        let c = DictationCoordinator(appState: app, hotkey: hk, engine: eng,
                                     cleanup: NoopCleanup(), inserter: ins)
        c.activate()
        hk.firePress(); await c.waitForStart()
        eng.emitFinal("不想要這段")
        c.cancel()

        XCTAssertTrue(eng.cancelled)
        XCTAssertEqual(app.state, .idle)
        XCTAssertTrue(ins.inserted.isEmpty)        // cancelled → nothing inserted
    }

    func testCancelWhenIdleIsNoOp() {
        let app = AppState(); let hk = FakeHotkey()
        let eng = FakeEngine()
        let c = DictationCoordinator(appState: app, hotkey: hk, engine: eng,
                                     cleanup: NoopCleanup(), inserter: FakeInserter())
        c.activate()
        c.cancel()
        XCTAssertFalse(eng.cancelled)
        XCTAssertEqual(app.state, .idle)
    }
}

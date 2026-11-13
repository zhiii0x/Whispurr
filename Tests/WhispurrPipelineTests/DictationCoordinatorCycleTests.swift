import XCTest
import WhispurrCore
@testable import WhispurrPipeline

/// Cycle isolation: work belonging to a cancelled / failed cycle must never act
/// on a later one, and failures must surface through `onError`.
@MainActor
final class DictationCoordinatorCycleTests: XCTestCase {
    final class FakeHotkey: HotkeySource {
        var onPress: (() -> Void)?
        var onRelease: (() -> Void)?
        private(set) var running = false
        func start() throws { running = true }
        func stop() { running = false }
    }

    final class FakeEngine: TranscriptionEngine {
        var onFinal: ((String) -> Void)?
        var onFailure: ((Error) -> Void)?
        var startError: Error?
        var blockStart = false
        var gate: CheckedContinuation<Void, Never>?
        private(set) var cancels = 0
        func start(onPartial: @escaping (String) -> Void,
                   onFinal: @escaping (String) -> Void) async throws {
            try await start(onPartial: onPartial, onFinal: onFinal, onFailure: { _ in })
        }
        func start(onPartial: @escaping (String) -> Void,
                   onFinal: @escaping (String) -> Void,
                   onFailure: @escaping (Error) -> Void) async throws {
            self.onFinal = onFinal
            self.onFailure = onFailure
            if blockStart { await withCheckedContinuation { gate = $0 } }
            if let startError { throw startError }
        }
        func stopAndFinalize() async throws {}
        func cancel() { cancels += 1 }
    }

    /// Worst case: ignores cancellation and parks every call until released.
    final class ParkingCleanup: TextCleanup {
        var parked: [CheckedContinuation<Void, Never>] = []
        func clean(_ text: String) async -> String {
            await withCheckedContinuation { parked.append($0) }
            return text
        }
    }

    final class RecordingInserter: TextInserter {
        private(set) var inserted: [String] = []
        func insert(_ text: String) { inserted.append(text) }
    }

    struct Boom: Error {}

    private func settle() async { for _ in 0..<20 { await Task.yield() } }

    /// Esc during cleanup, then re-dictate: when the cancelled take's cleanup
    /// finally returns (while the new take is still processing) it must neither
    /// insert its text nor end the new take.
    func testCancelledCleanupCannotHijackNextCycle() async {
        let app = AppState(), hk = FakeHotkey(), eng = FakeEngine()
        let cleanup = ParkingCleanup(), ins = RecordingInserter()
        let c = DictationCoordinator(appState: app, hotkey: hk, engine: eng,
                                     cleanup: cleanup, inserter: ins)
        var s = AppSettings(); s.cleanupEnabled = true
        c.updateSettings(s)
        c.activate()

        hk.onPress?(); await c.waitForStart()
        eng.onFinal?("A 取消的內容")
        hk.onRelease?(); await settle()
        XCTAssertEqual(cleanup.parked.count, 1)
        c.cancel()

        hk.onPress?(); await c.waitForStart()
        eng.onFinal?("B 重講的內容")
        hk.onRelease?(); await settle()
        XCTAssertEqual(cleanup.parked.count, 2)

        cleanup.parked[0].resume(); await settle()      // A returns mid-B
        XCTAssertTrue(ins.inserted.isEmpty)
        XCTAssertEqual(app.state, .processing)

        cleanup.parked[1].resume(); await c.waitForCycle()
        XCTAssertEqual(ins.inserted, ["B 重講的內容"])
        XCTAssertEqual(app.state, .idle)
    }

    /// A start that fails *after* the user cancelled is not an error.
    func testStartErrorAfterCancelIsIgnored() async {
        let app = AppState(), hk = FakeHotkey(), eng = FakeEngine()
        let c = DictationCoordinator(appState: app, hotkey: hk, engine: eng,
                                     cleanup: ParkingCleanup(), inserter: RecordingInserter())
        var errors = 0
        c.onError = { _ in errors += 1 }
        c.activate()
        eng.blockStart = true
        eng.startError = CancellationError()

        hk.onPress?(); await settle()
        c.cancel()
        eng.gate?.resume(); await c.waitForStart()

        XCTAssertEqual(app.state, .idle)
        XCTAssertEqual(errors, 0)
    }

    func testStartErrorReachesOnError() async {
        let app = AppState(), hk = FakeHotkey(), eng = FakeEngine()
        let c = DictationCoordinator(appState: app, hotkey: hk, engine: eng,
                                     cleanup: ParkingCleanup(), inserter: RecordingInserter())
        var received: Error?
        c.onError = { received = $0 }
        c.activate()
        eng.startError = AppleSpeechTranscriberEngine.EngineError.micDenied

        hk.onPress?(); await c.waitForStart()

        XCTAssertEqual(received as? AppleSpeechTranscriberEngine.EngineError, .micDenied)
        guard case .error = app.state else { return XCTFail("expected .error, got \(app.state)") }
    }

    /// The recognizer dying mid-take surfaces as an error instead of going deaf.
    func testRuntimeFailureWhileListeningSurfaces() async {
        let app = AppState(), hk = FakeHotkey(), eng = FakeEngine(), ins = RecordingInserter()
        let c = DictationCoordinator(appState: app, hotkey: hk, engine: eng,
                                     cleanup: ParkingCleanup(), inserter: ins)
        var errors = 0
        c.onError = { _ in errors += 1 }
        c.activate()

        hk.onPress?(); await c.waitForStart()
        eng.onFinal?("x")
        eng.onFailure?(Boom())

        guard case .error = app.state else { return XCTFail("expected .error, got \(app.state)") }
        XCTAssertEqual(errors, 1)
        hk.onRelease?(); await settle()
        XCTAssertTrue(ins.inserted.isEmpty)
    }

    /// Pausing while the key is held abandons the take (its key-up can't arrive).
    func testStopWhileListeningCancelsTheTake() async throws {
        let app = AppState(), hk = FakeHotkey(), eng = FakeEngine()
        let c = DictationCoordinator(appState: app, hotkey: hk, engine: eng,
                                     cleanup: ParkingCleanup(), inserter: RecordingInserter())
        c.activate()
        try c.start()

        hk.onPress?(); await c.waitForStart()
        c.stop()

        XCTAssertEqual(app.state, .idle)
        XCTAssertEqual(eng.cancels, 1)
        XCTAssertFalse(hk.running)
    }
}

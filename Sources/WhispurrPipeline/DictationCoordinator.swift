import Foundation
import os
import WhispurrCore

/// Owns the dictation state machine and the recognition pipeline. The only
/// mutator of AppState (so the Phase 1 onChange → CatAnimator path drives the
/// cat). On a completed cycle it cleans the transcript on-device, applies the
/// user's vocabulary rules, and inserts it at the cursor; `onTranscript`
/// surfaces the final text (e.g. for the menu).
@MainActor public final class DictationCoordinator {
    private var machine = DictationStateMachine()
    private let appState: AppState
    private let hotkey: HotkeySource
    private let engine: TranscriptionEngine
    private let cleanup: TextCleanup
    private var inserter: TextInserter

    /// Called with the finalized, cleaned transcript at the end of a cycle.
    public var onTranscript: ((String) -> Void)?
    /// Called with each volatile partial (recognizer preview during listening, and
    /// the cleanup stream during processing) for the HUD.
    public var onPartial: ((String) -> Void)?
    /// Called when a cycle finished but nothing was recognized (silence / misfire).
    public var onEmpty: (() -> Void)?

    private var settings = AppSettings()

    private var finalText = ""
    private var startTask: Task<Void, Never>?
    private var cycleTask: Task<Void, Never>?
    private var failResetTask: Task<Void, Never>?
    private var listenWatchdog: Task<Void, Never>?

    public init(appState: AppState, hotkey: HotkeySource, engine: TranscriptionEngine,
                cleanup: TextCleanup, inserter: TextInserter) {
        self.appState = appState
        self.hotkey = hotkey
        self.engine = engine
        self.cleanup = cleanup
        self.inserter = inserter
    }

    /// Apply a new settings snapshot (cleanup on/off, vocabulary, max listen).
    public func updateSettings(_ newSettings: AppSettings) { settings = newSettings }
    /// Swap the inserter (e.g. the user changed paste↔type mode).
    public func setInserter(_ newInserter: TextInserter) { inserter = newInserter }

    public func activate() {
        hotkey.onPress = { [weak self] in self?.handlePress() }
        hotkey.onRelease = { [weak self] in self?.handleRelease() }
    }

    public func start() throws { try hotkey.start() }
    public func stop() { hotkey.stop() }

    private func handlePress() {
        guard machine.state == .idle else { return }
        Log.pipeline.info("▶︎ key down → recording")
        failResetTask?.cancel(); failResetTask = nil
        finalText = ""
        appState.set(machine.handle(.pushToTalkDown))            // → .listening
        startListenWatchdog()
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.engine.start(
                    onPartial: { [weak self] p in self?.onPartial?(p) },
                    onFinal: { [weak self] f in
                        guard let self else { return }
                        self.finalText = TranscriptJoiner.join(self.finalText, f)
                    }
                )
            } catch {
                self.fail(error)
            }
        }
    }

    /// Cap a single utterance so a stuck-down / missed key-up can't hold the mic
    /// (and the cat) in .listening forever.
    private func startListenWatchdog() {
        listenWatchdog?.cancel()
        let limit = max(5, settings.maxListenSeconds)
        listenWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard let self, self.machine.state == .listening else { return }
            Log.pipeline.notice("max listen (\(Int(limit))s) reached — auto-finalizing")
            self.handleRelease()
        }
    }

    private func handleRelease() {
        guard machine.state == .listening else { return }
        listenWatchdog?.cancel(); listenWatchdog = nil
        Log.pipeline.info("⏹ key up → finalizing")
        appState.set(machine.handle(.pushToTalkUp))             // → .processing
        let clock = ContinuousClock()
        let tStart = clock.now
        cycleTask = Task { [weak self] in
            guard let self else { return }
            await self.startTask?.value                          // ensure start settled
            guard self.machine.state == .processing else { return }   // failed/cancelled meanwhile
            do {
                try await self.engine.stopAndFinalize()
            } catch {
                Log.pipeline.error("finalize failed: \(String(describing: error), privacy: .public)")
            }
            let tFinalized = clock.now
            guard self.machine.state == .processing else { return }   // cancelled during finalize
            let text = self.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                self.appState.set(self.machine.handle(.transcriptionFinished))   // → .idle
                self.onEmpty?()                                                  // flash after idle so it isn't hidden
                return
            }
            var cleaned = text
            if self.settings.cleanupEnabled {
                cleaned = await self.cleanup.clean(text, onPartial: { [weak self] p in
                    self?.onPartial?(p)                          // stream cleanup into the HUD
                })
            }
            guard self.machine.state == .processing else { return }   // cancelled during cleanup → don't insert
            let final = VocabularyManager(rules: self.settings.vocabulary).apply(to: cleaned)
            self.inserter.insert(final)
            self.onTranscript?(final)                            // surface the final text
            let tInserted = clock.now
            Log.pipeline.info(
                "latency: finalize \(Self.ms(tStart, tFinalized))ms, cleanup \(Self.ms(tFinalized, tInserted))ms, total \(Self.ms(tStart, tInserted))ms")
            self.appState.set(self.machine.handle(.transcriptionFinished))  // → .idle
        }
    }

    /// User aborted (Esc / Cmd-.): stop everything and discard without inserting.
    public func cancel() {
        guard machine.state == .listening || machine.state == .processing else { return }
        Log.pipeline.info("✦ cancelled by user")
        listenWatchdog?.cancel(); listenWatchdog = nil
        startTask?.cancel(); cycleTask?.cancel()
        engine.cancel()
        finalText = ""
        appState.set(machine.handle(.cancel))                   // → .idle, no insert
    }

    private func fail(_ error: Error) {
        Log.pipeline.error("✖︎ error: \(String(describing: error), privacy: .public)")
        listenWatchdog?.cancel(); listenWatchdog = nil
        engine.cancel()
        appState.set(machine.handle(.failed(String(describing: error))))   // → .error
        failResetTask?.cancel()
        failResetTask = Task { [weak self] in
            try? await Task.sleep(for: Timeouts.errorReset)
            guard let self, case .error = self.machine.state else { return }   // only reset if still erroring
            self.appState.set(self.machine.handle(.reset))                  // → .idle
        }
    }

    private static func ms(_ a: ContinuousClock.Instant, _ b: ContinuousClock.Instant) -> Int {
        let d = b - a
        return Int(Double(d.components.seconds) * 1000
                   + Double(d.components.attoseconds) / 1_000_000_000_000_000)
    }

    // MARK: Test hooks
    func waitForStart() async { await startTask?.value }
    func waitForCycle() async { await cycleTask?.value }
}

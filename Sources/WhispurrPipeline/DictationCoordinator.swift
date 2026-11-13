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
    /// Called (after the state moves to `.error`) with the error that ended a
    /// cycle, so the app can tell the user what went wrong.
    public var onError: ((Error) -> Void)?

    private var settings = AppSettings()

    private var finalText = ""
    private var startTask: Task<Void, Never>?
    private var cycleTask: Task<Void, Never>?
    private var failResetTask: Task<Void, Never>?
    private var listenWatchdog: Task<Void, Never>?

    /// Identifies the current dictation cycle. Bumped on every press, cancel and
    /// failure. Async work captures the id it started with and drops its result
    /// once it no longer matches — so a cancelled cycle whose finalize/cleanup is
    /// still in flight can never insert its text into (or idle out) a later cycle.
    private var cycle = 0

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

    /// Stop listening for the hotkey (the menu's Pause). A take that is still
    /// being recorded is abandoned: with the tap gone its key-up can never arrive,
    /// which would otherwise leave the mic open until the max-listen watchdog.
    public func stop() {
        hotkey.stop()
        if machine.state == .listening { cancel() }
    }

    private func handlePress() {
        guard machine.state == .idle else { return }
        cycle &+= 1
        let id = cycle
        Log.pipeline.info("▶︎ key down → recording")
        failResetTask?.cancel(); failResetTask = nil
        finalText = ""
        appState.set(machine.handle(.pushToTalkDown))            // → .listening
        startListenWatchdog(cycle: id)
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.engine.start(
                    onPartial: { [weak self] p in
                        guard let self, self.cycle == id else { return }
                        self.onPartial?(p)
                    },
                    onFinal: { [weak self] f in
                        guard let self, self.cycle == id else { return }
                        self.finalText = TranscriptJoiner.join(self.finalText, f)
                    },
                    onFailure: { [weak self] error in
                        // Only while still recording: a failure during finalize is
                        // left to the cycle, which inserts whatever was captured.
                        guard let self, self.cycle == id, self.machine.state == .listening else { return }
                        self.fail(error)
                    }
                )
            } catch {
                guard self.cycle == id else { return }           // cancelled meanwhile — not a failure
                self.fail(error)
            }
        }
    }

    /// Cap a single utterance so a stuck-down / missed key-up can't hold the mic
    /// (and the cat) in .listening forever.
    private func startListenWatchdog(cycle id: Int) {
        listenWatchdog?.cancel()
        let limit = max(5, settings.maxListenSeconds)
        listenWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(limit))
            guard !Task.isCancelled, let self, self.cycle == id,
                  self.machine.state == .listening else { return }
            Log.pipeline.notice("max listen (\(Int(limit))s) reached — auto-finalizing")
            self.handleRelease()
        }
    }

    private func handleRelease() {
        guard machine.state == .listening else { return }
        let id = cycle
        listenWatchdog?.cancel(); listenWatchdog = nil
        Log.pipeline.info("⏹ key up → finalizing")
        appState.set(machine.handle(.pushToTalkUp))             // → .processing
        let clock = ContinuousClock()
        let tStart = clock.now
        cycleTask = Task { [weak self] in
            guard let self else { return }
            await self.startTask?.value                          // ensure start settled
            guard self.isLive(id) else { return }
            do {
                try await self.engine.stopAndFinalize()
            } catch {
                Log.pipeline.error("finalize failed: \(String(describing: error), privacy: .public)")
            }
            let tFinalized = clock.now
            guard self.isLive(id) else { return }
            let text = self.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                self.appState.set(self.machine.handle(.transcriptionFinished))   // → .idle
                self.onEmpty?()                                                  // flash after idle so it isn't hidden
                return
            }
            var cleaned = text
            if self.settings.cleanupEnabled {
                cleaned = await self.cleanup.clean(text, onPartial: { [weak self] p in
                    guard let self, self.cycle == id else { return }   // stream cleanup into the HUD
                    self.onPartial?(p)
                })
            }
            guard self.isLive(id) else { return }                         // cancelled during cleanup → don't insert
            let final = VocabularyManager(rules: self.settings.vocabulary).apply(to: cleaned)
            self.inserter.insert(final)
            self.onTranscript?(final)                            // surface the final text
            let tInserted = clock.now
            Log.pipeline.info(
                "latency: finalize \(Self.ms(tStart, tFinalized))ms, cleanup \(Self.ms(tFinalized, tInserted))ms, total \(Self.ms(tStart, tInserted))ms")
            self.appState.set(self.machine.handle(.transcriptionFinished))  // → .idle
        }
    }

    /// Is cycle `id` still the one being processed (not cancelled, failed or
    /// superseded)? Checked after every await in the release path.
    private func isLive(_ id: Int) -> Bool {
        !Task.isCancelled && cycle == id && machine.state == .processing
    }

    /// User aborted (Esc): stop everything and discard without inserting.
    public func cancel() {
        guard machine.state == .listening || machine.state == .processing else { return }
        Log.pipeline.info("✦ cancelled by user")
        cycle &+= 1                                              // orphan any in-flight work
        listenWatchdog?.cancel(); listenWatchdog = nil
        startTask?.cancel(); cycleTask?.cancel()                 // cleanup forwards this to the LLM
        engine.cancel()
        finalText = ""
        appState.set(machine.handle(.cancel))                   // → .idle, no insert
    }

    private func fail(_ error: Error) {
        Log.pipeline.error("✖︎ error: \(String(describing: error), privacy: .public)")
        cycle &+= 1                                              // orphan the failed cycle's work
        listenWatchdog?.cancel(); listenWatchdog = nil
        startTask?.cancel(); cycleTask?.cancel()
        engine.cancel()
        appState.set(machine.handle(.failed(String(describing: error))))   // → .error
        onError?(error)
        failResetTask?.cancel()
        failResetTask = Task { [weak self] in
            try? await Task.sleep(for: Timeouts.errorReset)
            guard !Task.isCancelled, let self, case .error = self.machine.state else { return }
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

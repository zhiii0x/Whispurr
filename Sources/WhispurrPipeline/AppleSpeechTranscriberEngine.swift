import Foundation
import Speech
import os
import WhispurrCore
@preconcurrency import AVFoundation

/// On-device zh-TW dictation via SpeechAnalyzer + SpeechTranscriber (macOS 26).
@available(macOS 26.0, *)
@MainActor public final class AppleSpeechTranscriberEngine: TranscriptionEngine {
    private let locale = Locale(identifier: "zh-TW")
    private var contextualPhrases: [String]
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var audio: AudioCapture?
    private var analyzerTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?
    // Held so teardown() can nil them: a result already hopped onto the main actor
    // must not deliver into the next cycle after we've torn down.
    private var onPartialSink: ((String) -> Void)?
    private var onFinalSink: ((String) -> Void)?
    private var onFailureSink: ((Error) -> Void)?

    /// Bumped by every `start()` and `cancel()`. Anything that suspends captures
    /// the value it began with and stands down if it changed — so a cancelled
    /// session can neither open the mic after the user aborted nor (via a late
    /// finalize/drain/error) tear down the session that replaced it.
    private var session = 0

    /// Per-launch caches: only the first dictation pays for the model check and
    /// the audio-format negotiation, so every later key-down reaches a live mic
    /// without a single await.
    private var modelReady = false
    private var analyzerFormat: AVAudioFormat?

    public init(contextualPhrases: [String] = AppleSpeechTranscriberEngine.defaultTechPhrases) {
        self.contextualPhrases = contextualPhrases
    }

    /// Update the recognizer's contextual phrase bias (e.g. the user edited their
    /// vocabulary). Takes effect on the next dictation cycle.
    public func setContextualPhrases(_ phrases: [String]) { contextualPhrases = phrases }

    /// Default tech jargon to bias zh↔en code-switched recognition toward.
    public static let defaultTechPhrases = [
        "push", "commit", "pull request", "merge", "rebase", "deploy", "build",
        "repo", "branch", "async", "await", "API", "endpoint", "database", "query",
        "cache", "Docker", "Kubernetes", "Swift", "Xcode", "TypeScript", "refactor",
        "debug", "staging", "production", "rollback",
    ]

    /// Speech auth (required even on-device) — call during onboarding.
    /// `nonisolated`: TCC invokes the completion handler on a background queue,
    /// so it must NOT be main-actor-isolated (else the runtime traps).
    nonisolated public static func requestSpeechAuth() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }

    /// Microphone auth — call during onboarding so the prompt appears up front
    /// rather than mid-way through the first dictation.
    nonisolated public static func requestMicAuth() async -> Bool {
        await AudioCapture.requestMic()
    }

    public func start(onPartial: @escaping (String) -> Void,
                      onFinal: @escaping (String) -> Void) async throws {
        try await start(onPartial: onPartial, onFinal: onFinal, onFailure: { _ in })
    }

    public func start(onPartial: @escaping (String) -> Void,
                      onFinal: @escaping (String) -> Void,
                      onFailure: @escaping (Error) -> Void) async throws {
        session &+= 1
        let id = session
        let clock = ContinuousClock()
        let t0 = clock.now
        onPartialSink = onPartial
        onFinalSink = onFinal
        onFailureSink = onFailure

        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted: throw EngineError.speechDenied
        default: break
        }

        let transcriber = Self.makeTranscriber(locale: locale)
        self.transcriber = transcriber

        // One-time per launch: make sure the zh-TW asset is on disk (downloading it
        // if the user skipped onboarding) and learn the analyzer's audio format.
        if !modelReady {
            Log.pipeline.info("engine: checking zh-TW model…")
            do {
                try await Self.ensureModelInstalled(for: transcriber, locale: locale)
            } catch let e as EngineError {
                throw e
            } catch {
                Log.pipeline.error("model install failed: \(String(describing: error), privacy: .public)")
                throw EngineError.modelUnavailable
            }
            modelReady = true
            try checkLive(id)
            Log.pipeline.info("zh-TW model ready")
        }
        let format: AVAudioFormat
        if let cached = analyzerFormat {
            format = cached
        } else {
            guard let f = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw EngineError.noAudioFormat
            }
            analyzerFormat = f
            format = f
            try checkLive(id)
        }
        if AVAudioApplication.shared.recordPermission != .granted {
            guard await AudioCapture.requestMic() else { throw EngineError.micDenied }
            try checkLive(id)
        }

        // Open the mic BEFORE building the analyzer. The stream buffers input until
        // the analyzer starts consuming it, so nothing said right after key-down is
        // lost to analyzer setup (it used to be: the mic only went live last).
        let capture = AudioCapture(targetFormat: format)
        let stream = capture.makeStream()
        do {
            try capture.start()
        } catch {
            capture.stop()
            Log.audio.error("mic start failed: \(String(describing: error), privacy: .public)")
            throw EngineError.audioInputFailed
        }
        self.audio = capture
        Log.audio.info("🎙 mic live \(Self.ms(t0, clock.now), privacy: .public)ms after start")

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        // Bias recognition toward the user's domain terms (code-switching help).
        if !contextualPhrases.isEmpty {
            let ctx = AnalysisContext()
            ctx.contextualStrings = [.general: contextualPhrases]
            try? await analyzer.setContext(ctx)
            try checkLive(id)   // cancelled meanwhile → cancel() already released the mic
        }

        // Deliver via the stored sinks, gated on the session, so a late result from
        // a cancelled session can't leak into the next one.
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let isFinal = result.isFinal
                    await MainActor.run {
                        guard let self, self.session == id else { return }
                        Log.content(isFinal ? "[final]" : "[partial]", text, to: Log.pipeline)
                        if isFinal { self.onFinalSink?(text) } else { self.onPartialSink?(text) }
                    }
                }
            } catch {
                let cancelled = Task.isCancelled
                await MainActor.run { self?.sessionFailed(id, error, source: "results", cancelled: cancelled) }
            }
        }

        analyzerTask = Task { [weak self] in
            do {
                try await analyzer.start(inputSequence: stream)
            } catch {
                let cancelled = Task.isCancelled
                await MainActor.run { self?.sessionFailed(id, error, source: "analyzer", cancelled: cancelled) }
            }
        }
        Log.pipeline.info("analyzer running")
    }

    public func stopAndFinalize() async throws {
        let id = session
        // Stop the mic first so the stream finishes, which signals end-of-input.
        audio?.stop()
        var finalizeError: Error?
        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
        } catch {
            finalizeError = error   // still drain + tear down below: nothing may outlive the session
        }
        guard session == id else { return }   // cancelled meanwhile; cancel() already tore down
        // Drain the consumer, but bound the wait: if `results` does not terminate
        // after finalize (an unverified macOS 26 contract), a watchdog cancels the
        // tasks so a dictation cycle can never wedge the coordinator in .processing.
        await drainBounded()
        guard session == id else { return }
        teardown()
        if let finalizeError { throw finalizeError }
    }

    /// Awaits the results/analyzer tasks, cancelling them if they don't finish
    /// within a grace period (cancellation makes the `for try await` loop exit).
    private func drainBounded(timeout: Duration = Timeouts.finalizeDrain) async {
        let results = resultsTask
        let analyzerWork = analyzerTask
        let watchdog = Task {
            try? await Task.sleep(for: timeout)
            results?.cancel()
            analyzerWork?.cancel()
        }
        await results?.value
        await analyzerWork?.value
        watchdog.cancel()
    }

    public func cancel() {
        session &+= 1
        audio?.stop()
        resultsTask?.cancel()
        analyzerTask?.cancel()
        teardown()
    }

    /// The recognizer died on its own. Ignored for stale sessions and for our own
    /// cancellations (teardown / drain watchdog); otherwise release the mic and
    /// report it so the user isn't left talking into a dead pipeline.
    private func sessionFailed(_ id: Int, _ error: Error, source: String, cancelled: Bool) {
        guard session == id, !cancelled, !(error is CancellationError) else { return }
        Log.pipeline.error("\(source, privacy: .public) error: \(String(describing: error), privacy: .public)")
        let report = onFailureSink
        modelReady = false   // re-verify the asset next time in case it was the cause
        teardown()
        report?(EngineError.recognitionFailed)
    }

    /// Throws if a `cancel()` (or a newer `start()`) superseded session `id`.
    private func checkLive(_ id: Int) throws {
        guard session == id else { throw CancellationError() }
    }

    private func teardown() {
        // Always release the mic hardware — the analyzer-error path used to nil
        // `audio` without stopping it, leaking a live tap + AVAudioEngine.
        audio?.stop()
        analyzer = nil; transcriber = nil; audio = nil
        resultsTask = nil; analyzerTask = nil
        onPartialSink = nil; onFinalSink = nil; onFailureSink = nil
    }

    private static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []        // (was [.audioTimeRange] — never read; carries cost)
        )
    }

    private static func ms(_ a: ContinuousClock.Instant, _ b: ContinuousClock.Instant) -> Int {
        let d = b - a
        return Int(Double(d.components.seconds) * 1000
                   + Double(d.components.attoseconds) / 1_000_000_000_000_000)
    }

    // MARK: - Model installation (one-time zh-TW asset)

    /// Whether the zh-TW recognition model is already on disk (no download needed).
    public static func isModelInstalled(locale: Locale = Locale(identifier: "zh-TW")) async -> Bool {
        let installed = await SpeechTranscriber.installedLocales
        return installed.contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }

    /// Download + install the model up front (e.g. during onboarding) so it never
    /// blocks the user's first dictation. `progress` reports 0...1 on the main actor.
    public static func prepareModel(locale: Locale = Locale(identifier: "zh-TW"),
                                    progress: (@MainActor (Double) -> Void)? = nil) async throws {
        try await ensureModelInstalled(for: makeTranscriber(locale: locale), locale: locale, progress: progress)
    }

    static func ensureModelInstalled(for transcriber: SpeechTranscriber,
                                     locale: Locale,
                                     progress: (@MainActor (Double) -> Void)? = nil) async throws {
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }) else {
            throw EngineError.localeUnsupported
        }
        let installed = await SpeechTranscriber.installedLocales
        if installed.contains(where: {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }) {
            if let progress { await MainActor.run { progress(1.0) } }
            return
        }
        Log.pipeline.notice("downloading zh-TW model… (one-time)")
        guard let req = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else {
            if let progress { await MainActor.run { progress(1.0) } }
            return
        }
        let poller: Task<Void, Never>? = progress.map { report in
            let p = req.progress
            return Task { @MainActor in
                while !Task.isCancelled {
                    report(p.fractionCompleted)
                    if p.isFinished { break }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        }
        defer { poller?.cancel() }
        try await req.downloadAndInstall()
        if let progress { await MainActor.run { progress(1.0) } }
    }

    /// Engine failures, kept coarse and user-meaningful so the app can show an
    /// actionable message instead of failing silently.
    public enum EngineError: Error, Equatable {
        case noAudioFormat       // the analyzer offered no compatible audio format
        case micDenied
        case speechDenied
        case localeUnsupported   // zh-TW recognition isn't available on this Mac
        case modelUnavailable    // zh-TW asset missing and couldn't be installed
        case audioInputFailed    // the mic / audio engine couldn't start
        case recognitionFailed   // the analyzer / results stream died mid-session
    }
}

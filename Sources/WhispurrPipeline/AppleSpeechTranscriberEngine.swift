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
        onPartialSink = onPartial
        onFinalSink = onFinal

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []        // (was [.audioTimeRange] — never read; carries cost)
        )
        self.transcriber = transcriber
        Log.pipeline.info("engine starting…")
        try await Self.ensureModelInstalled(for: transcriber, locale: locale)
        Log.pipeline.info("zh-TW model ready")

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        // Bias recognition toward the user's domain terms (code-switching help).
        if !contextualPhrases.isEmpty {
            let ctx = AnalysisContext()
            ctx.contextualStrings = [.general: contextualPhrases]
            try? await analyzer.setContext(ctx)
        }

        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        guard let format else { throw EngineError.noAudioFormat }

        let capture = AudioCapture(targetFormat: format)
        self.audio = capture
        guard await AudioCapture.requestMic() else { throw EngineError.micDenied }

        // Build the stream before starting capture so the tap is installed.
        let stream = capture.makeStream()

        // Consume results in a separate task before handing the stream to the
        // analyzer, so we don't miss early results. Deliver via the stored sinks
        // (niled on teardown) so a late result can't leak into the next cycle.
        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    let isFinal = result.isFinal
                    await MainActor.run {
                        guard let self else { return }
                        Log.content(isFinal ? "[final]" : "[partial]", text, to: Log.pipeline)
                        if isFinal { self.onFinalSink?(text) } else { self.onPartialSink?(text) }
                    }
                }
            } catch {
                Log.pipeline.error("results error: \(String(describing: error), privacy: .public)")
            }
        }

        analyzerTask = Task { [weak self] in
            do {
                try await analyzer.start(inputSequence: stream)
            } catch {
                await MainActor.run { self?.teardown() }
            }
        }

        try capture.start()
        Log.audio.info("🎙 listening (analyzer + mic running)")
    }

    public func stopAndFinalize() async throws {
        // Stop the mic first so the stream finishes, which signals end-of-input.
        audio?.stop()
        try await analyzer?.finalizeAndFinishThroughEndOfInput()
        // Drain the consumer, but bound the wait: if `results` does not terminate
        // after finalize (an unverified macOS 26 contract), a watchdog cancels the
        // tasks so a dictation cycle can never wedge the coordinator in .processing.
        await drainBounded()
        teardown()
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
        audio?.stop()
        resultsTask?.cancel()
        analyzerTask?.cancel()
        teardown()
    }

    private func teardown() {
        // Always release the mic hardware — the analyzer-error path used to nil
        // `audio` without stopping it, leaking a live tap + AVAudioEngine.
        audio?.stop()
        analyzer = nil; transcriber = nil; audio = nil
        resultsTask = nil; analyzerTask = nil
        onPartialSink = nil; onFinalSink = nil
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
        let transcriber = SpeechTranscriber(
            locale: locale, transcriptionOptions: [],
            reportingOptions: [.volatileResults], attributeOptions: [])
        try await ensureModelInstalled(for: transcriber, locale: locale, progress: progress)
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

    enum EngineError: Error { case noAudioFormat, micDenied, localeUnsupported }
}

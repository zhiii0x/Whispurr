import Foundation
import os
import WhispurrCore
@preconcurrency import AVFoundation
import Speech

/// Taps the microphone and converts buffers to the format the analyzer wants,
/// yielding `AnalyzerInput` on a stream. The tap runs on a realtime thread, so
/// stay lock-free and only yield to the buffered continuation.
@available(macOS 26.0, *)
final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var configObserver: (any NSObjectProtocol)?

    init(targetFormat: AVAudioFormat) { self.targetFormat = targetFormat }

    /// Request mic permission (AVAudioApplication; macOS 14+).
    static func requestMic() async -> Bool {
        if AVAudioApplication.shared.recordPermission == .granted { return true }
        return await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    func makeStream() -> AsyncStream<AnalyzerInput> {
        AsyncStream { continuation in
            self.continuation = continuation
            let input = engine.inputNode
            let hwFormat = input.outputFormat(forBus: 0)
            let conv = AVAudioConverter(from: hwFormat, to: targetFormat)
            conv?.primeMethod = .none
            self.converter = conv
            input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
                guard let self, let out = self.convert(buffer) else { return }
                self.continuation?.yield(AnalyzerInput(buffer: out))
            }
        }
    }

    func start() throws {
        engine.prepare()
        // If the hardware input route changes mid-dictation (AirPods unplugged,
        // input device switched), the tap/converter become invalid and would
        // silently emit nothing. Finish the stream so the cycle finalizes with
        // whatever was captured rather than hanging on an empty transcript.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Log.audio.notice("audio configuration changed mid-capture — finishing stream")
            self?.continuation?.finish()
        }
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)   // guarantees the tap block won't fire again…
        engine.stop()
        continuation?.finish()                  // …before we tear down the continuation
        continuation = nil
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
    }

    private func convert(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter, input.format.sampleRate > 0 else { return nil }
        // Size the output to the actual converted frame count (≈ inputFrames *
        // rateRatio) rather than a full second of audio. A FRESH buffer each call
        // is required: it is handed to the analyzer asynchronously, so reusing one
        // would corrupt an in-flight buffer the consumer hasn't read yet.
        let ratio = targetFormat.sampleRate / input.format.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                         frameCapacity: max(capacity, 1)) else { return nil }
        // The converter calls the input block synchronously (once per convert call).
        // Use a reference cell to satisfy Swift 6 Sendable checking without unsafe casts.
        final class Once: @unchecked Sendable { var fed = false }
        let once = Once()
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if once.fed { status.pointee = .noDataNow; return nil }
            once.fed = true; status.pointee = .haveData; return input
        }
        return err == nil ? out : nil
    }
}

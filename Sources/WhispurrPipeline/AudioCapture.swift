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
            self.installTap(format: engine.inputNode.outputFormat(forBus: 0))
        }
    }

    func start() throws {
        engine.prepare()
        // A hardware input route change fires this notification. The important
        // (and previously-broken) case: Bluetooth mics (AirPods) flip from the
        // A2DP playback route to the HFP "call" route the instant capture starts —
        // so a configuration change arrives ~immediately, BEFORE any audio. The old
        // code finished the stream here, which is exactly why AirPods recorded pure
        // silence ("speaking, no response"). Instead, rebuild the tap + converter
        // against the new route's format and keep capturing. Only finish if there's
        // no valid input left (e.g. the sole mic was unplugged mid-dictation), so a
        // genuine device-loss still finalizes with whatever was captured.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }
        try engine.start()
    }

    func stop() {
        // Remove the observer FIRST: engine.stop() itself can fire a configuration
        // change, and we must not re-enter the handler (which would rebuild the tap)
        // while tearing down.
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)   // guarantees the tap block won't fire again…
        engine.stop()
        continuation?.finish()                  // …before we tear down the continuation
        continuation = nil
    }

    /// Install (or reinstall) the input tap + converter for `hwFormat`. Re-runnable:
    /// `removeTap` drains any prior tap before we swap the converter, so the realtime
    /// block never reads a converter that doesn't match its buffers.
    private func installTap(format hwFormat: AVAudioFormat) {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let conv = AVAudioConverter(from: hwFormat, to: targetFormat)
        conv?.primeMethod = .none
        self.converter = conv
        input.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { [weak self] buffer, _ in
            guard let self, let out = self.convert(buffer) else { return }
            self.continuation?.yield(AnalyzerInput(buffer: out))
        }
    }

    /// React to a mid-capture route change (see `start()`): rebuild against the new
    /// input format and keep going, or finish if no usable input remains.
    private func handleConfigurationChange() {
        guard let continuation else { return }   // already torn down / not capturing
        let hwFormat = engine.inputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            Log.audio.notice("audio route lost (no valid input) — finishing stream")
            continuation.finish()
            return
        }
        Log.audio.notice(
            "audio route changed — rebuilding tap @ \(Int(hwFormat.sampleRate), privacy: .public)Hz \(hwFormat.channelCount, privacy: .public)ch")
        installTap(format: hwFormat)
        if !engine.isRunning {
            do { try engine.start() }
            catch {
                Log.audio.error("engine restart after route change failed: \(String(describing: error), privacy: .public)")
                continuation.finish()
            }
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

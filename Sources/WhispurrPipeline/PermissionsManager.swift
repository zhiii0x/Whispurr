import Foundation
import AVFoundation
import Speech
import CoreGraphics
import ApplicationServices
import FoundationModels

/// Reads the real TCC / Apple-Intelligence state into a PermissionSnapshot,
/// and exposes request entry points. Status reads are synchronous best-effort;
/// requests are async (they may prompt or open Settings).
@MainActor public final class PermissionsManager {
    public init() {}

    public func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
            speech: SFSpeechRecognizer.authorizationStatus() == .authorized,
            // CGPreflightListenEventAccess() is side-effect-free on macOS 13+
            // (the .macOS("26.0") floor in Package.swift guarantees this), so
            // polling snapshot() reads the grant without ever prompting.
            inputMonitoring: CGPreflightListenEventAccess(),
            accessibility: AXIsProcessTrusted(),
            appleIntelligence: appleIntelligenceAvailable()
        )
    }

    public func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// `nonisolated`: TCC calls the completion handler on a background queue, so
    /// it must not be main-actor-isolated (else the runtime traps on reply).
    nonisolated public func requestSpeech() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }

    /// Opens the Input Monitoring Settings pane; the process usually must relaunch.
    public func requestInputMonitoring() { _ = CGRequestListenEventAccess() }

    /// Opens the Accessibility Settings pane with the system prompt.
    public func requestAccessibility() {
        // kAXTrustedCheckOptionPrompt is a CFStringRef C global whose Swift 6
        // import is not Sendable-annotated, causing a shared-mutable-state error.
        // Use the known string value directly to stay concurrency-safe.
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private func appleIntelligenceAvailable() -> Bool {
        // Foundation Models has no TCC permission; its gate is the AI toggle,
        // surfaced via SystemLanguageModel availability.
        if #available(macOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        return false
    }
}

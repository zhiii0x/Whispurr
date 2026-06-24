import SwiftUI
import AppKit
import WhispurrPipeline

@MainActor final class PermissionsViewModel: ObservableObject {
    enum Item: CaseIterable, Identifiable {
        case inputMonitoring, microphone, speech, accessibility
        var id: Self { self }
        @MainActor var title: String {
            switch self {
            case .inputMonitoring: return L10n.t(.permInputTitle)
            case .microphone:      return L10n.t(.permMicTitle)
            case .speech:          return L10n.t(.permSpeechTitle)
            case .accessibility:   return L10n.t(.permAxTitle)
            }
        }
        @MainActor var why: String {
            switch self {
            case .inputMonitoring: return L10n.t(.permInputWhy)
            case .microphone:      return L10n.t(.permMicWhy)
            case .speech:          return L10n.t(.permSpeechWhy)
            case .accessibility:   return L10n.t(.permAxWhy)
            }
        }
    }

    private let permissions = PermissionsManager()
    @Published private(set) var snapshot: PermissionSnapshot
    /// 0...1 while the zh-TW model downloads; nil when not downloading.
    @Published private(set) var modelProgress: Double?
    private var timer: Timer?
    private var downloading = false

    /// Fired once when Input Monitoring transitions ungranted → granted, so the
    /// app can re-arm the hotkey without requiring a relaunch.
    var onInputMonitoringGranted: (() -> Void)?

    init() { snapshot = permissions.snapshot() }

    var canStart: Bool { snapshot.canDictate }
    var appleIntelligence: Bool { snapshot.appleIntelligence }

    func granted(_ item: Item) -> Bool {
        switch item {
        case .inputMonitoring: return snapshot.inputMonitoring
        case .microphone:      return snapshot.microphone
        case .speech:          return snapshot.speech
        case .accessibility:   return snapshot.accessibility
        }
    }

    func startPolling() {
        timer?.invalidate()                 // idempotent: never run two timers
        refresh()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    func stopPolling() { timer?.invalidate(); timer = nil }

    func refresh() {
        let was = snapshot
        snapshot = permissions.snapshot()
        if !was.inputMonitoring && snapshot.inputMonitoring { onInputMonitoringGranted?() }
    }

    /// Download the zh-TW recognition model up front (with progress) so it never
    /// blocks the first dictation. Idempotent: no-op if already installed or
    /// already in flight.
    func downloadModelIfNeeded() {
        guard !downloading else { return }
        downloading = true
        Task { @MainActor in
            defer { downloading = false }
            if await AppleSpeechTranscriberEngine.isModelInstalled() { return }
            modelProgress = 0
            try? await AppleSpeechTranscriberEngine.prepareModel { [weak self] f in
                self?.modelProgress = f
            }
            modelProgress = nil
        }
    }

    /// Grant action: prompts for mic/speech; opens the Settings pane for the
    /// permissions that can only be toggled there.
    func grant(_ item: Item) {
        switch item {
        case .microphone:
            Task { _ = await permissions.requestMicrophone(); refresh() }
        case .speech:
            Task { _ = await permissions.requestSpeech(); refresh() }
        case .inputMonitoring:
            permissions.requestInputMonitoring()
            openPane("Privacy_ListenEvent")
        case .accessibility:
            permissions.requestAccessibility()
            openPane("Privacy_Accessibility")
        }
    }

    func openKeyboardSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
    }
    private func openPane(_ anchor: String) {
        open("x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }
    private func open(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }
}

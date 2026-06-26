import AppKit
import os
import WhispurrCore
import WhispurrPipeline

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private let permissions = PermissionsManager()
    private let settingsStore = SettingsStore()
    private let hud = FloatingHUD()
    private lazy var onboarding = OnboardingWindow()
    private lazy var settingsWindow = SettingsWindow(store: settingsStore)

    private var menuBar: MenuBarController!
    private var coordinator: DictationCoordinator!
    private var hotkey: HotkeyManager!
    private var engine: AppleSpeechTranscriberEngine!

    private var lastApplied: AppSettings?
    private var escMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = settingsStore.settings
        L10n.lang = settings.language          // before any UI is built

        menuBar = MenuBarController()
        menuBar.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        menuBar.onOpenPermissions = { [weak self] in self?.onboarding.show() }
        menuBar.onToggleEnabled = { [weak self] on in self?.setEnabled(on) }

        appState.onChange = { [weak self] state in
            guard let self else { return }
            self.menuBar.update(state)
            self.hud.update(state)
            self.playCue(for: state)
        }

        // Build the pipeline from settings (composition root).
        let components = AppAssembly.make(appState: appState, settings: settings)
        coordinator = components.coordinator
        hotkey = components.hotkey
        engine = components.engine
        coordinator.activate()
        coordinator.onTranscript = { [weak self] text in
            self?.menuBar.setLastTranscript(text)
            Log.content("transcript", text, to: Log.app)
        }
        coordinator.onPartial = { [weak self] partial in self?.hud.showPartial(partial) }
        coordinator.onEmpty = { [weak self] in self?.hud.flashMessage(L10n.t(.hudHeardNothing)) }

        menuBar.setAIAvailable(permissions.snapshot().appleIntelligence)
        appState.set(.idle)

        // Apply settings changes from the Settings window (diffed in apply()).
        settingsStore.onChange = { [weak self] s in self?.apply(s) }
        lastApplied = settings

        // Esc cancels an in-progress dictation. We're an accessory app, so the
        // target app is frontmost → a global monitor is the right tool (it only
        // observes; coordinator.cancel() no-ops unless mid-cycle).
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.coordinator.cancel() }
        }

        // Request mic + speech auth early so both prompts appear on first run.
        Task {
            _ = await AppleSpeechTranscriberEngine.requestMicAuth()
            _ = await AppleSpeechTranscriberEngine.requestSpeechAuth()
            self.menuBar.setAIAvailable(self.permissions.snapshot().appleIntelligence)
        }

        FoundationModelsCleanup.prewarmIfAvailable()
        LoginItem.apply(settings.launchAtLogin)

        // Re-arm the hotkey the moment Input Monitoring is granted — no relaunch.
        onboarding.onInputMonitoringGranted = { [weak self] in self?.startHotkey() }
        startHotkey()

        // First-run guidance: onboarding handles permissions AND a missing model
        // (so the multi-hundred-MB download happens here with a progress bar,
        // never silently on the first dictation).
        Task {
            let snap = permissions.snapshot()
            let modelReady = await AppleSpeechTranscriberEngine.isModelInstalled()
            if !snap.canDictate || !modelReady { onboarding.show() }
        }

        // Opt-in update check: one anonymous GitHub request, only when enabled.
        // Surfaces as a menu-bar item if a newer release exists; never installs.
        if settings.checkForUpdatesAutomatically {
            Task {
                if case let .available(version, url) = await UpdateCheck.latest(currentVersion: AppInfo.version) {
                    self.menuBar.setUpdateAvailable(version: version, url: url)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let escMonitor { NSEvent.removeMonitor(escMonitor) }
    }

    private func startHotkey() {
        do {
            try coordinator.start()
        } catch {
            // Input Monitoring not yet granted — the onboarding window guides it,
            // and onInputMonitoringGranted will retry this automatically.
            Log.app.notice("Input Monitoring needed — see the welcome window")
        }
    }

    private func setEnabled(_ on: Bool) {
        if on { startHotkey() } else { coordinator.stop() }
        menuBar.setEnabled(on)
    }

    /// Apply a settings change, doing the minimum work (so editing a vocabulary
    /// text field doesn't restart the event tap on every keystroke).
    private func apply(_ s: AppSettings) {
        let old = lastApplied
        if old?.language != s.language {
            L10n.lang = s.language
            menuBar.applyLanguage()
        }
        coordinator.updateSettings(s)
        if old?.insertionMode != s.insertionMode || old?.restoreClipboard != s.restoreClipboard {
            coordinator.setInserter(SystemTextInserter(mode: s.insertionMode,
                                                       restoreClipboard: s.restoreClipboard))
        }
        if old?.hotkey != s.hotkey {
            hotkey.reconfigure(detector: PushToTalkEdgeDetector(preset: s.hotkey))
        }
        if old?.vocabulary != s.vocabulary {
            engine.setContextualPhrases(AppAssembly.contextualPhrases(for: s))
        }
        if old?.launchAtLogin != s.launchAtLogin {
            LoginItem.apply(s.launchAtLogin)
        }
        lastApplied = s
    }

    private func playCue(for state: DictationState) {
        guard settingsStore.settings.soundCues else { return }
        switch state {
        case .listening:  Cue.recordingStarted()
        case .processing: Cue.recordingStopped()
        default: break
        }
    }
}

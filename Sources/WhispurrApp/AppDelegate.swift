import AppKit
import os
import WhispurrCore
import WhispurrPipeline

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private let permissions = PermissionsManager()
    private let settingsStore = SettingsStore()
    private let hud = FloatingHUD()
    private lazy var settingsWindow = SettingsWindow(store: settingsStore)

    private var menuBar: MenuBarController!
    private var coordinator: DictationCoordinator!
    private var hotkey: HotkeyManager!
    private var engine: AppleSpeechTranscriberEngine!

    private var lastApplied: AppSettings?
    private var escMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)               // Dock icon
        NSApp.mainMenu = buildMainMenu(settingsTarget: self,
                                       settingsAction: #selector(openSettingsFromMenu))
        let settings = settingsStore.settings
        L10n.lang = settings.language          // before any UI is built

        menuBar = MenuBarController()
        menuBar.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        menuBar.onOpenPermissions = { [weak self] in self?.settingsWindow.show(tab: .permissions) }
        menuBar.onToggleEnabled = { [weak self] on in self?.setEnabled(on) }
        menuBar.onToggleCleanup = { [weak self] on in self?.setCleanupEnabled(on) }

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
        menuBar.setCleanupEnabled(settings.cleanupEnabled)
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

        // Re-arm the hotkey when Input Monitoring is granted while a permissions
        // view is polling. As a backstop, applicationDidBecomeActive re-checks on
        // every app activation (e.g. returning from System Settings); macOS may
        // still need a relaunch for a fresh event-tap grant to take effect.
        settingsWindow.onInputMonitoringGranted = { [weak self] in self?.startHotkey() }
        startHotkey()

        // First run: show the setup wizard (a sheet in the single window).
        if !settings.hasCompletedOnboarding { settingsWindow.showOnboarding() }

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

    /// Re-sync permission-derived state whenever the app comes forward — covers the
    /// user enabling Apple Intelligence or granting Input Monitoring in System
    /// Settings and switching back. `startHotkey()` is idempotent (no-op if armed).
    func applicationDidBecomeActive(_ notification: Notification) {
        let snap = permissions.snapshot()
        menuBar.setAIAvailable(snap.appleIntelligence)
        if snap.inputMonitoring { startHotkey() }
    }

    @objc func openSettingsFromMenu() { settingsWindow.show() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // keep running in the menu bar / Dock after windows close
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if settingsStore.settings.hasCompletedOnboarding { settingsWindow.show() }
            else { settingsWindow.showOnboarding() }
        }
        return true
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

    /// Toggle the on-device cleanup preference (the menu's quick "fast mode" switch).
    /// Persisting fires the store's onChange → apply() → coordinator.updateSettings.
    private func setCleanupEnabled(_ on: Bool) {
        settingsStore.update { $0.cleanupEnabled = on }
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
        if old?.cleanupEnabled != s.cleanupEnabled {
            menuBar.setCleanupEnabled(s.cleanupEnabled)   // keep the menu toggle in sync
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

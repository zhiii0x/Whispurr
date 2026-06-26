import AppKit
import SwiftUI
import WhispurrCore

/// Owns the onboarding NSWindow. Reusable: `show()` brings it forward.
@MainActor final class OnboardingWindow {
    private var window: NSWindow?
    private let vm = PermissionsViewModel()
    private let settingsVM: SettingsViewModel
    private let store: SettingsStore

    /// Forwarded from the permissions VM: fires when Input Monitoring is granted
    /// so the app can re-arm the hotkey without a relaunch.
    var onInputMonitoringGranted: (() -> Void)? {
        didSet { vm.onInputMonitoringGranted = onInputMonitoringGranted }
    }

    init(store: SettingsStore) {
        self.store = store
        self.settingsVM = SettingsViewModel(store: store)
    }

    func show() {
        if let window {
            vm.startPolling()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingFlow(perms: vm, settingsVM: settingsVM) { [weak self] in
            self?.store.update { $0.hasCompletedOnboarding = true }
            self?.close()
        }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = L10n.t(.obWindowTitle)
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.close() }
}

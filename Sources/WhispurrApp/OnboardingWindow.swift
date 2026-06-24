import AppKit
import SwiftUI

/// Owns the onboarding NSWindow. Reusable: `show()` brings it forward.
@MainActor final class OnboardingWindow {
    private var window: NSWindow?
    private let vm = PermissionsViewModel()

    /// Forwarded from the view model: fires when Input Monitoring is granted so
    /// the app can re-arm the hotkey without a relaunch.
    var onInputMonitoringGranted: (() -> Void)? {
        didSet { vm.onInputMonitoringGranted = onInputMonitoringGranted }
    }

    func show() {
        if let window {
            vm.startPolling()               // resume live status on reopen
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingView(vm: vm) { [weak self] in self?.close() }
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

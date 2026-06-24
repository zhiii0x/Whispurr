import ServiceManagement
import os
import WhispurrCore

/// Launch-at-login via SMAppService. Requires a properly bundled, signed .app to
/// actually take effect; calls are best-effort and logged on failure (e.g. when
/// running unsigned via `swift run`).
@MainActor enum LoginItem {
    static func apply(_ enabled: Bool) {
        do {
            let service = SMAppService.mainApp
            if enabled {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
        } catch {
            Log.app.error("login item update failed: \(String(describing: error), privacy: .public)")
        }
    }
}

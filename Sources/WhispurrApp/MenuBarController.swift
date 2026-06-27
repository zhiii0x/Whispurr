import AppKit
import WhispurrCore

/// Owns the `NSStatusItem`, its animated cat, and the menu. Reflects dictation
/// state and exposes menu actions via callbacks (kept out of AppDelegate so the
/// launch path stays a thin composition root). Titles are localized via L10n and
/// refreshed on a language change; no emoji in the menu.
@MainActor final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let animator: CatAnimator

    private let updateItem    = NSMenuItem()
    private let updateSep     = NSMenuItem.separator()
    private let lastItem     = NSMenuItem()
    private let copyItem      = NSMenuItem()
    private let aiItem        = NSMenuItem()
    private let toggleItem    = NSMenuItem()
    private let settingsItem  = NSMenuItem()
    private let permsItem      = NSMenuItem()
    private let quitItem       = NSMenuItem()

    private var lastTranscript = ""
    private var enabled = true
    private var aiAvailable = false
    private var cleanupEnabled = true
    private var updateVersion: String?
    private var updateURL: URL?

    var onToggleEnabled: ((Bool) -> Void)?
    var onToggleCleanup: ((Bool) -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenPermissions: (() -> Void)?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        animator = CatAnimator(button: statusItem.button!)
        super.init()
        buildMenu()
        applyLanguage()
    }

    func update(_ state: DictationState) { animator.update(to: state) }

    func setLastTranscript(_ text: String) {
        lastTranscript = text
        let shown = text.count > 40 ? String(text.prefix(40)) + "…" : text
        lastItem.title = text.isEmpty ? L10n.t(.recentNone) : L10n.t(.recentPrefix) + shown
        copyItem.isEnabled = !text.isEmpty
    }

    /// Whether the on-device cleanup model is available (gates the toggle).
    func setAIAvailable(_ available: Bool) {
        aiAvailable = available
        refreshCleanupItem()
    }

    /// Reflect the user's cleanup preference (the menu's quick on/off "fast mode").
    func setCleanupEnabled(_ on: Bool) {
        cleanupEnabled = on
        refreshCleanupItem()
    }

    /// The cleanup row is a checkmark toggle: checked when cleanup will actually
    /// run (enabled AND the model is available), and disabled when Apple
    /// Intelligence is off (toggling it would have no effect).
    private func refreshCleanupItem() {
        aiItem.title = L10n.t(.fieldCleanup)
        aiItem.state = (cleanupEnabled && aiAvailable) ? .on : .off
        aiItem.isEnabled = aiAvailable
        aiItem.toolTip = aiAvailable ? nil : L10n.t(.obAIOff)
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        toggleItem.title = on ? L10n.t(.pause) : L10n.t(.resume)
    }

    /// Surface a newer release at the top of the menu. Clicking it opens the
    /// GitHub release page; the app never downloads or installs anything itself.
    func setUpdateAvailable(version: String, url: URL) {
        updateVersion = version
        updateURL = url
        updateItem.title = L10n.t(.menuUpdateAvailable, version)
        updateItem.isHidden = false
        updateSep.isHidden = false
    }

    /// Re-title every item after a language change.
    func applyLanguage() {
        if let updateVersion { updateItem.title = L10n.t(.menuUpdateAvailable, updateVersion) }
        setLastTranscript(lastTranscript)
        copyItem.title = L10n.t(.copyLast)
        setAIAvailable(aiAvailable)
        setEnabled(enabled)
        settingsItem.title = L10n.t(.menuSettings)
        permsItem.title = L10n.t(.menuPermissions)
        quitItem.title = L10n.t(.quit)
    }

    private func buildMenu() {
        let menu = NSMenu()
        // Hidden until a check finds a newer release; then surfaces at the top.
        updateItem.target = self; updateItem.action = #selector(openUpdate)
        updateItem.isHidden = true; updateSep.isHidden = true
        menu.addItem(updateItem)
        menu.addItem(updateSep)
        lastItem.isEnabled = false
        menu.addItem(lastItem)
        copyItem.target = self; copyItem.action = #selector(copyLast)
        copyItem.keyEquivalent = "c"; copyItem.isEnabled = false
        menu.addItem(copyItem)
        menu.addItem(.separator())
        aiItem.target = self; aiItem.action = #selector(toggleCleanup)
        menu.addItem(aiItem)
        toggleItem.target = self; toggleItem.action = #selector(toggleEnabled)
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        settingsItem.target = self; settingsItem.action = #selector(openSettings)
        menu.addItem(settingsItem)
        permsItem.target = self; permsItem.action = #selector(openPermissions)
        menu.addItem(permsItem)
        menu.addItem(.separator())
        quitItem.action = #selector(NSApplication.terminate(_:)); quitItem.keyEquivalent = "q"
        menu.addItem(quitItem)
        statusItem.menu = menu
        menu.delegate = self
        stripSystemImages(menu)
    }

    /// Defensive backstop for macOS 26's auto SF Symbol decoration of recognized
    /// rows (設定 → gear, 結束 → quit symbol, 權限 → …). The PRIMARY fix lives in
    /// main.swift, which disables the feature via the NSMenuEnableActionImages
    /// default — necessary because the system re-stamps the image at *display* time
    /// (read back through NSMenuItem.image's getter), so clearing it via the setter
    /// here can only ever race and the icon flashes in before being cleared. With
    /// the default off nothing gets stamped, so this is a harmless no-op kept as
    /// belt-and-suspenders (and to keep titles flush-left if the default regresses).
    private func stripSystemImages(_ menu: NSMenu) {
        menu.update()
        menu.items.forEach { $0.image = nil }
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        setEnabled(enabled)
        onToggleEnabled?(enabled)
    }

    @objc private func toggleCleanup() {
        guard aiAvailable else { return }
        cleanupEnabled.toggle()
        refreshCleanupItem()
        onToggleCleanup?(cleanupEnabled)
    }

    @objc private func copyLast() {
        guard !lastTranscript.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(lastTranscript, forType: .string)
    }

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func openPermissions() { onOpenPermissions?() }
    @objc private func openUpdate() { if let updateURL { NSWorkspace.shared.open(updateURL) } }
}

extension MenuBarController: NSMenuDelegate {
    /// Re-strip the system's auto SF Symbols every time the menu opens — covers
    /// re-decoration after a language change re-titles the rows.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.forEach { $0.image = nil }
    }
}

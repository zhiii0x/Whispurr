import AppKit
import WhispurrCore

/// Owns the `NSStatusItem`, its animated cat, and the menu. Reflects dictation
/// state and exposes menu actions via callbacks (kept out of AppDelegate so the
/// launch path stays a thin composition root). Titles are localized via L10n and
/// refreshed on a language change; no emoji in the menu.
@MainActor final class MenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private let animator: CatAnimator

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

    var onToggleEnabled: ((Bool) -> Void)?
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

    func setAIAvailable(_ available: Bool) {
        aiAvailable = available
        aiItem.title = available ? L10n.t(.cleanupOn) : L10n.t(.cleanupOff)
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        toggleItem.title = on ? L10n.t(.pause) : L10n.t(.resume)
    }

    /// Re-title every item after a language change.
    func applyLanguage() {
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
        lastItem.isEnabled = false
        menu.addItem(lastItem)
        copyItem.target = self; copyItem.action = #selector(copyLast)
        copyItem.keyEquivalent = "c"; copyItem.isEnabled = false
        menu.addItem(copyItem)
        menu.addItem(.separator())
        aiItem.isEnabled = false
        menu.addItem(aiItem)
        toggleItem.target = self; toggleItem.action = #selector(toggleEnabled)
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        settingsItem.target = self; settingsItem.action = #selector(openSettings)
        settingsItem.keyEquivalent = ","
        menu.addItem(settingsItem)
        permsItem.target = self; permsItem.action = #selector(openPermissions)
        menu.addItem(permsItem)
        menu.addItem(.separator())
        quitItem.action = #selector(NSApplication.terminate(_:)); quitItem.keyEquivalent = "q"
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        setEnabled(enabled)
        onToggleEnabled?(enabled)
    }

    @objc private func copyLast() {
        guard !lastTranscript.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(lastTranscript, forType: .string)
    }

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func openPermissions() { onOpenPermissions?() }
}

import AppKit
import SwiftUI
import WhispurrCore

/// Owns the Settings NSWindow. Reusable: `show()` brings it forward.
@MainActor final class SettingsWindow {
    private var window: NSWindow?
    private let store: SettingsStore

    init(store: SettingsStore) { self.store = store }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(vm: SettingsViewModel(store: store))
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = L10n.t(.settingsTitle)
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Bridges the AppKit-free `SettingsStore` to SwiftUI bindings. Writes back to
/// the store on every change (the store de-dupes no-op writes), and keeps the
/// live UI language in sync so the form re-localizes instantly.
@MainActor final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            L10n.lang = settings.language     // before the body re-renders
            store.replace(settings)
        }
    }
    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
        self.settings = store.settings
        L10n.lang = store.settings.language
    }

    func addRule() { settings.vocabulary.append(VocabularyRule(from: "", to: "")) }
    func removeRule(_ id: UUID) { settings.vocabulary.removeAll { $0.id == id } }
}

struct SettingsView: View {
    @ObservedObject var vm: SettingsViewModel
    @StateObject private var updates = UpdateModel()

    var body: some View {
        Form {
            Section(L10n.t(.secInput)) {
                Picker(L10n.t(.fieldLanguage), selection: $vm.settings.language) {
                    ForEach(Language.allCases) { Text($0.nativeName).tag($0) }
                }
                Picker(L10n.t(.fieldHotkey), selection: $vm.settings.hotkey) {
                    ForEach(HotkeyPreset.allCases) { Text(L10n.hotkey($0)).tag($0) }
                }
                Picker(L10n.t(.fieldInsertion), selection: $vm.settings.insertionMode) {
                    ForEach(InsertionMode.allCases) { Text(L10n.insertion($0)).tag($0) }
                }
                Toggle(L10n.t(.fieldRestoreClipboard), isOn: $vm.settings.restoreClipboard)
            }

            Section(L10n.t(.secCleanup)) {
                Toggle(L10n.t(.fieldCleanup), isOn: $vm.settings.cleanupEnabled)
                Text(L10n.t(.noteCleanup)).font(.caption).foregroundStyle(.secondary)
            }

            Section(L10n.t(.secBehavior)) {
                Toggle(L10n.t(.fieldSoundCues), isOn: $vm.settings.soundCues)
                Toggle(L10n.t(.fieldLaunchAtLogin), isOn: $vm.settings.launchAtLogin)
                HStack {
                    Text(L10n.t(.fieldMaxListen))
                    Slider(value: $vm.settings.maxListenSeconds, in: 10...300, step: 5)
                    Text("\(Int(vm.settings.maxListenSeconds))s").monospacedDigit().frame(width: 44)
                }
            }

            Section(L10n.t(.secVocab)) {
                ForEach($vm.settings.vocabulary) { $rule in
                    HStack(spacing: 8) {
                        TextField(L10n.t(.vocabFrom), text: $rule.from)
                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                        TextField(L10n.t(.vocabTo), text: $rule.to)
                        Toggle("Aa", isOn: $rule.caseSensitive)
                            .toggleStyle(.button).help(L10n.t(.caseSensitive))
                        Button(role: .destructive) { vm.removeRule(rule.id) } label: {
                            Image(systemName: "trash")
                        }.buttonStyle(.borderless)
                    }
                }
                Button { vm.addRule() } label: { Label(L10n.t(.addRule), systemImage: "plus") }
            }

            Section(L10n.t(.secAbout)) {
                LabeledContent("Whispurr", value: AppInfo.displayVersion)
                LabeledContent(L10n.t(.aboutMadeBy), value: "zhiii0x")
                updateRow
                Toggle(L10n.t(.fieldAutoUpdate), isOn: $vm.settings.checkForUpdatesAutomatically)
                Link(destination: URL(string: "https://github.com/zhiii0x/Whispurr")!) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://x.com/zhiii0x")!) {
                    Label("X (@zhiii0x)", systemImage: "at")
                }
                Link(destination: URL(string: "https://nono.today")!) {
                    Label("nono.today", systemImage: "globe")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 700)
        .onAppear {
            if vm.settings.checkForUpdatesAutomatically, updates.state == .idle { updates.check() }
        }
    }

    /// "Check for Updates" button with an inline result. The download link opens
    /// the GitHub release page — we never auto-install (the user re-downloads the
    /// signed DMG, so Gatekeeper trust is untouched).
    @ViewBuilder private var updateRow: some View {
        HStack {
            Button(L10n.t(.checkUpdates)) { updates.check() }
                .disabled(updates.state == .checking)
            Spacer()
            switch updates.state {
            case .idle:
                EmptyView()
            case .checking:
                ProgressView().controlSize(.small)
            case .upToDate:
                Text(L10n.t(.upToDate)).font(.caption).foregroundStyle(.secondary)
            case .failed:
                Text(L10n.t(.updateFailed)).font(.caption).foregroundStyle(.secondary)
            case let .available(version, url):
                Link(L10n.t(.downloadUpdate, version), destination: url)
            }
        }
    }
}

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
        TabView {
            generalTab
                .tabItem { Label(L10n.t(.tabGeneral), systemImage: "gearshape") }
            dictationTab
                .tabItem { Label(L10n.t(.tabDictation), systemImage: "mic") }
            vocabularyTab
                .tabItem { Label(L10n.t(.tabVocabulary), systemImage: "textformat") }
            aboutTab
                .tabItem { Label(L10n.t(.secAbout), systemImage: "info.circle") }
        }
        .frame(width: 480, height: 380)
        .onAppear {
            if vm.settings.checkForUpdatesAutomatically, updates.state == .idle { updates.check() }
        }
    }

    // MARK: - Tabs

    private var generalTab: some View {
        Form {
            Section {
                Picker(L10n.t(.fieldLanguage), selection: $vm.settings.language) {
                    ForEach(Language.allCases) { Text($0.nativeName).tag($0) }
                }
                Toggle(L10n.t(.fieldSoundCues), isOn: $vm.settings.soundCues)
                Toggle(L10n.t(.fieldLaunchAtLogin), isOn: $vm.settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
    }

    private var dictationTab: some View {
        Form {
            Section {
                Picker(L10n.t(.fieldHotkey), selection: $vm.settings.hotkey) {
                    ForEach(HotkeyPreset.allCases) { Text(L10n.hotkey($0)).tag($0) }
                }
                Picker(L10n.t(.fieldInsertion), selection: $vm.settings.insertionMode) {
                    ForEach(InsertionMode.allCases) { Text(L10n.insertion($0)).tag($0) }
                }
                Toggle(L10n.t(.fieldRestoreClipboard), isOn: $vm.settings.restoreClipboard)
                LabeledContent(L10n.t(.fieldMaxListen)) {
                    HStack {
                        Slider(value: $vm.settings.maxListenSeconds, in: 10...300, step: 5)
                            .frame(width: 160)
                        Text("\(Int(vm.settings.maxListenSeconds))s").monospacedDigit().frame(width: 36)
                    }
                }
            }
            Section {
                Toggle(isOn: $vm.settings.cleanupEnabled) {
                    Text(L10n.t(.fieldCleanup))
                    Text(L10n.t(.noteCleanup)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var vocabularyTab: some View {
        Form {
            Section {
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
            } footer: {
                Text(L10n.t(.secVocab)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Centered "hero" about page: app icon, name, version, credit, an update
    /// check, and a row of links. Intentionally NOT a Form — a calmer layout than
    /// the settings tabs.
    private var aboutTab: some View {
        VStack(spacing: 11) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)

            VStack(spacing: 3) {
                Text("Whispurr").font(.title2.bold())
                Text(AppInfo.displayVersion).font(.callout).foregroundStyle(.secondary)
            }

            Text("\(L10n.t(.aboutMadeBy)) zhiii0x")
                .font(.callout).foregroundStyle(.secondary)

            Divider().frame(width: 200).padding(.vertical, 2)

            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Button(L10n.t(.checkUpdates)) { updates.check() }
                        .disabled(updates.state == .checking)
                    updateStatus
                }
                Toggle(L10n.t(.fieldAutoUpdate), isOn: $vm.settings.checkForUpdatesAutomatically)
                    .toggleStyle(.checkbox)
            }

            Spacer().frame(height: 18)

            HStack(spacing: 24) {
                aboutLink("GitHub", "chevron.left.forwardslash.chevron.right",
                          "https://github.com/zhiii0x/Whispurr")
                aboutLink("X", "at", "https://x.com/zhiii0x")
                aboutLink("nono.today", "globe", "https://nono.today")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 16)
    }

    /// A vertical icon-over-label link, tinted, used in the About footer row.
    private func aboutLink(_ title: String, _ symbol: String, _ urlString: String) -> some View {
        Link(destination: URL(string: urlString)!) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption)
            }
            .frame(minWidth: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    /// Inline result of an update check. The download link opens the GitHub
    /// release page — we never auto-install (the user re-downloads the signed
    /// DMG, so Gatekeeper trust is untouched).
    @ViewBuilder private var updateStatus: some View {
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

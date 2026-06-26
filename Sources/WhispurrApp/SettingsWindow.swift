import AppKit
import SwiftUI
import WhispurrCore

/// The app's single window. Hosts the settings tabs (incl. a Permissions tab) and
/// presents the first-run / replayable setup wizard as a sheet *inside this same
/// window* — so the app only ever opens one window, never a stack of them.
enum SettingsTab: Hashable { case general, dictation, vocabulary, permissions, about }

@MainActor final class SettingsWindowModel: ObservableObject {
    @Published var selectedTab: SettingsTab = .general
    @Published var showOnboarding = false
}

/// Owns the single NSWindow and the view models shared by the settings tabs and
/// the setup wizard (one PermissionsViewModel so polling / hotkey re-arm is
/// unified). Reusable: `show(tab:)` / `showOnboarding()` bring it forward.
@MainActor final class SettingsWindow {
    private var window: NSWindow?
    private let store: SettingsStore
    private let model = SettingsWindowModel()
    private let perms = PermissionsViewModel()
    private lazy var vm = SettingsViewModel(store: store)

    /// Forwarded from the permissions VM: fires when Input Monitoring is granted
    /// so the app can re-arm the hotkey without a relaunch.
    var onInputMonitoringGranted: (() -> Void)? {
        didSet { perms.onInputMonitoringGranted = onInputMonitoringGranted }
    }

    init(store: SettingsStore) { self.store = store }

    /// Bring the window forward on a given tab (default General).
    func show(tab: SettingsTab = .general) {
        ensureWindow()
        model.selectedTab = tab
        bringForward()
    }

    /// Bring the window forward and present the setup wizard sheet over it.
    func showOnboarding() {
        ensureWindow()
        model.showOnboarding = true
        bringForward()
    }

    private func ensureWindow() {
        guard window == nil else { return }
        let root = SettingsRoot(model: model, vm: vm, perms: perms, store: store)
        let w = NSWindow(contentViewController: NSHostingController(rootView: root))
        w.title = L10n.t(.settingsTitle)
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
    }

    private func bringForward() {
        window?.makeKeyAndOrderFront(nil)
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

/// Window root: the settings tabs with the setup wizard layered on as a sheet, so
/// "tutorial" and "settings" live in one window.
struct SettingsRoot: View {
    @ObservedObject var model: SettingsWindowModel
    @ObservedObject var vm: SettingsViewModel
    @ObservedObject var perms: PermissionsViewModel
    let store: SettingsStore

    var body: some View {
        SettingsView(model: model, vm: vm, perms: perms)
            .sheet(isPresented: $model.showOnboarding) {
                OnboardingFlow(perms: perms, settingsVM: vm) {
                    store.update { $0.hasCompletedOnboarding = true }
                    model.showOnboarding = false
                }
            }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsWindowModel
    @ObservedObject var vm: SettingsViewModel
    @ObservedObject var perms: PermissionsViewModel
    @StateObject private var updates = UpdateModel()

    var body: some View {
        TabView(selection: $model.selectedTab) {
            generalTab
                .tabItem { Label(L10n.t(.tabGeneral), systemImage: "gearshape") }
                .tag(SettingsTab.general)
            dictationTab
                .tabItem { Label(L10n.t(.tabDictation), systemImage: "mic") }
                .tag(SettingsTab.dictation)
            vocabularyTab
                .tabItem { Label(L10n.t(.tabVocabulary), systemImage: "textformat") }
                .tag(SettingsTab.vocabulary)
            permissionsTab
                .tabItem { Label(L10n.t(.permWindowTitle), systemImage: "lock.shield") }
                .tag(SettingsTab.permissions)
            aboutTab
                .tabItem { Label(L10n.t(.secAbout), systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 480, height: 380)
        .padding(.top, 12)            // drop the tab bar down off the title bar
        // Match the onboarding wizard's look: soft gradient backdrop, always light.
        // (The grouped Forms' own backgrounds are hidden below so this shows through.)
        .background(UIStyle.softBackground)
        .environment(\.colorScheme, .light)
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
            Section(L10n.t(.replayGuide)) {
                Button(L10n.t(.replayGuideButton)) { model.showOnboarding = true }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)   // reveal the window's soft gradient
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
        .scrollContentBackground(.hidden)   // reveal the window's soft gradient
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
        .scrollContentBackground(.hidden)   // reveal the window's soft gradient
    }

    /// The same permission checklist the setup wizard shows, now also reachable as
    /// a tab (the menu's "Permissions…" opens the window here).
    private var permissionsTab: some View {
        OnboardingPermissions(vm: perms)
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

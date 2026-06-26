import SwiftUI
import WhispurrCore

struct OnboardingKeySettings: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t(.keySetupTitle)).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
            VStack(spacing: 10) {
                row(L10n.t(.fieldLanguage)) {
                    Picker("", selection: $vm.settings.language) {
                        ForEach(Language.allCases) { Text($0.nativeName).tag($0) }
                    }.labelsHidden().fixedSize()
                }
                row(L10n.t(.fieldHotkey)) {
                    Picker("", selection: $vm.settings.hotkey) {
                        ForEach(HotkeyPreset.allCases) { Text(L10n.hotkey($0)).tag($0) }
                    }.labelsHidden().fixedSize()
                }
                row(L10n.t(.fieldInsertion)) {
                    Picker("", selection: $vm.settings.insertionMode) {
                        ForEach(InsertionMode.allCases) { Text(L10n.insertion($0)).tag($0) }
                    }.labelsHidden().fixedSize()
                }
                row(L10n.t(.fieldCleanup)) {
                    Toggle("", isOn: $vm.settings.cleanupEnabled).labelsHidden()
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: UIStyle.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: UIStyle.cardRadius).strokeBorder(.white.opacity(0.8)))
        }
        .padding(.horizontal, 24).padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private func row<Control: View>(_ label: String, @ViewBuilder _ control: () -> Control) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            control()
        }
    }
}

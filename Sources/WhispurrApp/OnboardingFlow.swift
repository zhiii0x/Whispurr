import SwiftUI

struct OnboardingFlow: View {
    @ObservedObject var perms: PermissionsViewModel
    @ObservedObject var settingsVM: SettingsViewModel
    let onFinish: () -> Void

    @State private var step = 0
    private let total = 6

    private var canAdvance: Bool {
        step == 1 ? perms.canStart : true   // permissions step gates Next
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: OnboardingHowItWorks()
                case 1: OnboardingPermissions(vm: perms)
                case 2: OnboardingAppleIntelligence(perms: perms, settingsVM: settingsVM)
                case 3: OnboardingKeySettings(vm: settingsVM)
                case 4: OnboardingTryIt()
                default: OnboardingDone()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.4)

            HStack {
                if step > 0 {
                    Button(L10n.t(.navBack)) { withAnimation { step -= 1 } }
                        .buttonStyle(.borderless)
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<total, id: \.self) { i in
                        Circle().fill(i == step ? UIStyle.accent : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                Button(step == total - 1 ? L10n.t(.navFinish) : L10n.t(.navNext)) {
                    if step == total - 1 { onFinish() } else { withAnimation { step += 1 } }
                }
                .controlSize(.large).buttonStyle(.borderedProminent).tint(UIStyle.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdvance)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 440, height: 520)
        // Always-available exit: ✕ (or Esc) dismisses the wizard. Calls onFinish so
        // it also marks onboarding seen — it won't auto-reappear; replay it anytime
        // from Settings → General → "Replay setup guide".
        .overlay(alignment: .topTrailing) {
            Button(action: onFinish) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(7)
                    .background(.white.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help(L10n.t(.navClose))
            .padding(10)
        }
        .background(UIStyle.softBackground)
        .environment(\.colorScheme, .light)
    }
}

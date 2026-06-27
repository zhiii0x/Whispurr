import SwiftUI

/// Onboarding step dedicated to the optional Apple Intelligence cleanup: explains
/// what it does, shows whether the on-device model is available with a shortcut to
/// enable it, and lets the user opt in (off by default).
struct OnboardingAppleIntelligence: View {
    @ObservedObject var perms: PermissionsViewModel
    @ObservedObject var settingsVM: SettingsViewModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: perms.appleIntelligence ? "sparkles" : "sparkles.slash")
                .font(.system(size: 44))
                .foregroundStyle(perms.appleIntelligence ? UIStyle.accent : .secondary)
                .shadow(color: .black.opacity(0.1), radius: 5, y: 3)

            VStack(spacing: 5) {
                Text(L10n.t(.obAITitle)).font(.title2.bold())
                Text(L10n.t(.obAIBody))
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 330)
            }

            VStack(spacing: 11) {
                HStack(spacing: 8) {
                    Image(systemName: perms.appleIntelligence ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(perms.appleIntelligence ? .green : .secondary.opacity(0.5))
                    Text(perms.appleIntelligence ? L10n.t(.obAIOn) : L10n.t(.obAIOff))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    if !perms.appleIntelligence {
                        Button(L10n.t(.obEnableAI)) { perms.openAppleIntelligenceSettings() }
                            .controlSize(.small).buttonStyle(.bordered).tint(UIStyle.accent)
                    }
                }
                Divider().opacity(0.35)
                Toggle(isOn: $settingsVM.settings.cleanupEnabled) {
                    Text(L10n.t(.fieldCleanup)).font(.system(size: 13, weight: .medium))
                }
                .toggleStyle(.switch).tint(UIStyle.accent)
                if settingsVM.settings.cleanupEnabled && !perms.appleIntelligence {
                    Text(L10n.t(.cleanupNeedsAI))
                        .font(.caption2).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(15)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: UIStyle.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: UIStyle.cardRadius).strokeBorder(.white.opacity(0.8)))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
        .padding(.horizontal, 24).padding(.top, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { perms.startPolling() }
        .onDisappear { perms.stopPolling() }
    }
}

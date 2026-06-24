import SwiftUI

struct OnboardingView: View {
    @ObservedObject var vm: PermissionsViewModel
    let onStart: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                if let cat = UIStyle.catImage("listening") {
                    Image(nsImage: cat).resizable()
                        .aspectRatio(contentMode: .fit).frame(width: 76, height: 76)
                        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                }
                Text("Whispurr").font(.title2).bold()
                Text(L10n.t(.obTagline))
                    .foregroundStyle(.secondary).font(.callout).multilineTextAlignment(.center)
            }

            VStack(spacing: 9) {
                ForEach(PermissionsViewModel.Item.allCases) { item in
                    HStack(spacing: 12) {
                        Image(systemName: vm.granted(item) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(vm.granted(item) ? Color.green : Color.secondary.opacity(0.5))
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: vm.granted(item))
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: vm.granted(item))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(.system(size: 13, weight: .semibold))
                            Text(item.why).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !vm.granted(item) {
                            Button(L10n.t(.obGrant)) { vm.grant(item) }
                                .controlSize(.small).buttonStyle(.bordered).tint(UIStyle.accent)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.white.opacity(0.66), in: RoundedRectangle(cornerRadius: UIStyle.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: UIStyle.cardRadius).strokeBorder(.white.opacity(0.7)))
                    .shadow(color: .black.opacity(0.05), radius: 3, y: 2)
                }
            }

            VStack(spacing: 6) {
                HStack {
                    Text(L10n.t(.obFnHint))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.t(.obOpenKeyboard)) { vm.openKeyboardSettings() }
                        .controlSize(.small).buttonStyle(.borderless)
                }
                HStack(spacing: 6) {
                    Image(systemName: vm.appleIntelligence ? "sparkles" : "sparkles.slash")
                        .foregroundStyle(vm.appleIntelligence ? UIStyle.accent : .secondary)
                    Text(vm.appleIntelligence ? L10n.t(.obAIOn) : L10n.t(.obAIOff))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if let p = vm.modelProgress {
                VStack(spacing: 4) {
                    ProgressView(value: p)
                    Text(L10n.t(.obModelDownloading, Int(p * 100)))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            Button(action: onStart) {
                Text(vm.canStart ? L10n.t(.obStart) : L10n.t(.obStartBlocked))
                    .frame(maxWidth: .infinity).fontWeight(.semibold)
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(UIStyle.accent)
            .disabled(!vm.canStart)
        }
        .padding(24)
        .frame(width: 420)
        .background(UIStyle.softBackground)
        .environment(\.colorScheme, .light)   // keep the cozy light theme in both modes
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.97)
        .onAppear {
            vm.startPolling()
            vm.downloadModelIfNeeded()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) { appeared = true }
        }
        .onDisappear { vm.stopPolling() }
    }
}

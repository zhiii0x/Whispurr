import SwiftUI

struct OnboardingTryIt: View {
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Text(L10n.t(.tryTitle)).font(.title3.bold())
            Text(L10n.t(.tryInstruction))
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(L10n.t(.tryPlaceholder)).foregroundStyle(.secondary.opacity(0.7))
                        .padding(.horizontal, 8).padding(.vertical, 8).allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .focused($focused)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(4)
            }
            .frame(height: 110)
            .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: UIStyle.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: UIStyle.cardRadius).strokeBorder(.white.opacity(0.8)))
        }
        .padding(.horizontal, 24).padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focused = true }
    }
}

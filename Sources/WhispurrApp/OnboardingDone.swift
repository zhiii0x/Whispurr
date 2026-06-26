import SwiftUI

struct OnboardingDone: View {
    var body: some View {
        VStack(spacing: 16) {
            if let cat = UIStyle.catImage("idle") {
                Image(nsImage: cat).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 78, height: 78)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            }
            Text(L10n.t(.doneTitle)).font(.title2.bold())
            Text(L10n.t(.doneBody))
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
        }
        .padding(.horizontal, 24).padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

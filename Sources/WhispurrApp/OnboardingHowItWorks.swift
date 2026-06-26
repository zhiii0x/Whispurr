import SwiftUI

struct OnboardingHowItWorks: View {
    var body: some View {
        VStack(spacing: 15) {
            if let cat = UIStyle.catImage("listening") {
                Image(nsImage: cat).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 78, height: 78)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            }
            VStack(spacing: 4) {
                Text("Whispurr").font(.title2.bold())
                Text(L10n.t(.obTagline)).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 13) {
                Text(L10n.t(.howTitle)).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                stepRow(kind: .fn,   text: L10n.t(.howStep1))
                stepRow(kind: .mic,  text: L10n.t(.howStep2))
                stepRow(kind: .text, text: L10n.t(.howStep3))
            }
            .padding(16)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: UIStyle.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: UIStyle.cardRadius).strokeBorder(.white.opacity(0.8)))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            Text(L10n.t(.howEscTip)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24).padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private enum Kind { case fn, mic, text }

    @ViewBuilder private func stepRow(kind: Kind, text: String) -> some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().fill(UIStyle.accent.opacity(0.14)).frame(width: 34, height: 34)
                switch kind {
                case .fn:
                    RoundedRectangle(cornerRadius: 5).fill(.white)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(UIStyle.accent.opacity(0.5)))
                        .overlay(Text("fn").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIStyle.accent))
                        .frame(width: 26, height: 20)
                case .mic:
                    Image(systemName: "waveform").font(.system(size: 15, weight: .semibold)).foregroundStyle(UIStyle.accent)
                case .text:
                    Image(systemName: "text.cursor").font(.system(size: 15, weight: .semibold)).foregroundStyle(UIStyle.accent)
                }
            }
            Text(text).font(.system(size: 13.5))
            Spacer()
        }
    }
}

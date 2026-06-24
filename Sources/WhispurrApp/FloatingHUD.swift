import AppKit
import SwiftUI
import WhispurrCore

/// Observable state for the HUD's SwiftUI content.
@MainActor final class HUDModel: ObservableObject {
    @Published var state: DictationState = .idle
    @Published var partialText: String = ""
    /// Drives the entrance/exit animation (separate from `state` so we can
    /// animate out before the panel is ordered away).
    @Published var visible: Bool = false
}

/// A borderless, non-activating floating panel that shows live dictation status.
/// It must NEVER become key/main or it would steal focus from the target app
/// (breaking ⌘V insertion).
@MainActor final class FloatingHUD {
    private let model = HUDModel()
    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 76),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false   // the SwiftUI card draws its own soft shadow
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true   // purely informational
        let host = NSHostingView(rootView: HUDView(model: model))
        host.frame = panel.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(host)
    }

    /// Drive visibility + state from the dictation state.
    func update(_ state: DictationState) {
        model.state = state
        switch state {
        case .listening, .processing:
            show()
        case .error:
            show()
            scheduleHide(after: .seconds(2))
        case .idle:
            scheduleHide(after: .milliseconds(120))   // let the final text flash briefly
        }
    }

    func showPartial(_ text: String) { model.partialText = text }

    /// Briefly surface a one-off message (e.g. "沒聽到聲音") while otherwise idle.
    func flashMessage(_ text: String) {
        model.partialText = text
        show()
        scheduleHide(after: .seconds(1))
    }

    private func show() {
        hideTask?.cancel(); hideTask = nil
        if !panel.isVisible {
            reposition()
            panel.orderFrontRegardless()   // never key/main
        }
        model.visible = true               // animates the card in (SwiftUI)
    }

    /// Animate the card out, then order the panel away once the exit finishes.
    private func scheduleHide(after delay: Duration) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            switch self.model.state {
            case .listening, .processing: return   // re-shown meanwhile
            default: break
            }
            self.model.visible = false             // animates the card out
            try? await Task.sleep(for: .milliseconds(260))   // match the exit spring
            switch self.model.state {
            case .listening, .processing: return
            default:
                self.panel.orderOut(nil)
                self.model.partialText = ""
            }
        }
    }

    /// Top-center of the main screen, just under the menu bar.
    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        let x = vf.midX - size.width / 2
        let y = vf.maxY - size.height - 16   // near the top, just under the menu bar
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

/// SwiftUI content: a soft card with the cat, animated bars, and live text.
/// Springs in (rise + slight scale, gentle overshoot) and out.
struct HUDView: View {
    @ObservedObject var model: HUDModel

    private var isListening: Bool { if case .listening = model.state { return true }; return false }
    private var isProcessing: Bool { if case .processing = model.state { return true }; return false }

    var body: some View {
        card
            .opacity(model.visible ? 1 : 0)
            .scaleEffect(model.visible ? 1 : 0.94, anchor: .bottom)
            .offset(y: model.visible ? 0 : 16)
            .animation(.spring(response: 0.34, dampingFraction: 0.72), value: model.visible)
    }

    private var card: some View {
        HStack(spacing: 10) {
            if let cat = catImage {
                Image(nsImage: cat).resizable().interpolation(.none)
                    .aspectRatio(contentMode: .fit).frame(width: 28, height: 28)
            }
            if isProcessing {
                ProgressView().controlSize(.small).tint(.white)
            } else {
                EqualizerBars(active: isListening).frame(width: 26, height: 16)
            }
            Text(displayText)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeOut(duration: 0.12), value: model.partialText)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(UIStyle.hudBackground, in: RoundedRectangle(cornerRadius: UIStyle.hudRadius))
        .overlay(RoundedRectangle(cornerRadius: UIStyle.hudRadius).strokeBorder(.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
        .padding(10)
    }

    private var catImage: NSImage? {
        UIStyle.catImage(isProcessing ? "menubar-processing" : "menubar-listening")
    }

    private var displayText: String {
        if !model.partialText.isEmpty { return model.partialText }
        if isProcessing { return L10n.t(.hudProcessing) }
        if isListening { return L10n.t(.hudListening) }
        return ""
    }
}

/// A time-animated equalizer (visual only — not real mic level). The bars ease
/// down to a calm dot when not actively listening.
struct EqualizerBars: View {
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2.5) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule()
                        .fill(UIStyle.accent)
                        .frame(width: 3, height: 16 * (active ? barHeight(i: i, t: t) : 0.18))
                        .animation(.easeInOut(duration: 0.18), value: active)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func barHeight(i: Int, t: Double) -> Double {
        // Layered sines per bar → organic, non-uniform motion.
        let v = sin(t * 7 + Double(i) * 1.1) * 0.6 + sin(t * 4.3 + Double(i)) * 0.4
        return 0.22 + 0.78 * abs(v)
    }
}

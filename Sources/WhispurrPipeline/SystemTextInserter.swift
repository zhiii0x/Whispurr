import AppKit
import CoreGraphics
import WhispurrCore

/// Inserts text into the focused app. Default: copy → synthetic ⌘V → restore the
/// prior clipboard. Fallback: type the string as Unicode key events (IME-heavy
/// fields). Both require the Accessibility permission (else CGEvent.post no-ops).
///
/// Lives in WhispurrPipeline (not the app target) so the clipboard restore logic
/// is unit-testable. The dictation text is tagged transient + concealed so it is
/// not synced via Universal Clipboard or captured by clipboard-manager history.
@MainActor public final class SystemTextInserter: TextInserter {
    private let mode: InsertionMode
    private let restoreClipboard: Bool

    public init(mode: InsertionMode = .paste, restoreClipboard: Bool = true) {
        self.mode = mode
        self.restoreClipboard = restoreClipboard
    }

    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    public func insert(_ text: String) {
        guard !text.isEmpty else { return }
        switch mode {
        case .paste: paste(text)
        case .type:  typeUnicode(text)
        }
    }

    /// Pure decision: restore the saved clipboard only if our text is still on it
    /// (changeCount unchanged) and there was something to restore. Extracted so it
    /// can be unit-tested without a live pasteboard.
    static func shouldRestore(currentChangeCount: Int, stamp: Int, savedIsEmpty: Bool) -> Bool {
        currentChangeCount == stamp && !savedIsEmpty
    }

    private func paste(_ text: String) {
        let pb = NSPasteboard.general
        // Snapshot the prior clipboard (all items + types) to restore afterwards.
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pb.pasteboardItems ?? []).map { item in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let data = item.data(forType: t) { d[t] = data } }
            return d
        }
        pb.clearContents()
        pb.setString(text, forType: .string)
        // Hide the dictated text from Universal Clipboard sync + clipboard managers.
        pb.setData(Data(), forType: Self.transientType)
        pb.setData(Data(), forType: Self.concealedType)
        let stamp = pb.changeCount

        sendCmdV()

        guard restoreClipboard else { return }
        Task { [weak self] in
            try? await Task.sleep(for: Timeouts.pasteSettle)
            self?.restore(saved, ifChangeCountIs: stamp)
        }
    }

    private func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], ifChangeCountIs stamp: Int) {
        let pb = NSPasteboard.general
        guard Self.shouldRestore(currentChangeCount: pb.changeCount, stamp: stamp,
                                 savedIsEmpty: saved.isEmpty) else { return }   // user/app changed it → leave ours
        pb.clearContents()
        let items = saved.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (t, d) in dict { item.setData(d, forType: t) }
            return item
        }
        pb.writeObjects(items)
        // Mark the restore transient too, so it isn't captured as a fresh history
        // entry (it's the user's own prior content — keep it concealment-neutral).
        pb.setData(Data(), forType: Self.transientType)
    }

    private func sendCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 9 // kVK_ANSI_V
        let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    private func typeUnicode(_ text: String) {
        let src = CGEventSource(stateID: .combinedSessionState)
        var chunk: [UniChar] = []
        func flush() {
            guard !chunk.isEmpty else { return }
            let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            chunk.withUnsafeBufferPointer { buf in
                e?.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            }
            e?.post(tap: .cgSessionEventTap)
            chunk.removeAll(keepingCapacity: true)
        }
        // Chunk by Character so a surrogate pair (or multi-unit grapheme) is
        // never split across two events.
        for ch in text {
            let units = Array(ch.utf16)
            if chunk.count + units.count > 20 { flush() }
            chunk.append(contentsOf: units)
        }
        flush()
    }
}

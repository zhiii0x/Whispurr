import Foundation
import FoundationModels
import WhispurrPipeline

/// Dev-only diagnostic: feed deliberately messy zh-TW transcripts straight into
/// FoundationModelsCleanup (no mic / recognizer) to SEE what the on-device cleanup
/// actually does — and whether the model is even available. Not shipped.
///   swift run WhispurrEval
@available(macOS 26.0, *)
@MainActor
enum Eval {
    /// Deliberately messy: no punctuation, fillers, run-ons, code-switch, a question.
    static let corpus: [String] = [
        "嗯那個我想說就是我們明天要不要先把這個功能做完然後再來看看其他的",
        "幫我把這個 bug 修一下然後 push 到 main 然後開一個 pull request",
        "欸所以這個 API 到底要怎麼串接你知道嗎",
        "我昨天晚上回到家以後先吃了個飯然後洗澡接著就開始寫程式寫到大概十二點多覺得很累就去睡了結果今天早上又爬不起來",
        "這次預算大概是三萬五然後我們需要分成三個階段第一階段先做研究第二階段做開發第三階段測試上線",
        "呃我覺得這個設計還可以啦但是顏色可能要再調一下然後字體好像有點太小",
    ]

    static func run() async {
        let availability = SystemLanguageModel.default.availability
        print("=== Apple Intelligence model availability: \(availability) ===\n")
        guard case .available = availability else {
            print("⚠️ Model NOT available → cleanup returns the raw text unchanged.")
            print("   That alone would explain '順稿沒感覺'. Enable Apple Intelligence / let the model finish downloading.")
            return
        }
        let cleanup = FoundationModelsCleanup()
        let clock = ContinuousClock()
        var changedCount = 0
        for (i, raw) in corpus.enumerated() {
            let t0 = clock.now
            let out = await cleanup.clean(raw)
            let dt = clock.now - t0
            let ms = Int(Double(dt.components.seconds) * 1000
                         + Double(dt.components.attoseconds) / 1_000_000_000_000_000)
            let changed = out != raw
            if changed { changedCount += 1 }
            print("[\(i + 1)] \(changed ? "✓ changed" : "⚠️ UNCHANGED")  (\(ms)ms, \(raw.count)→\(out.count) chars)")
            print("  raw: \(raw)")
            print("  out: \(out)")
            print()
        }
        print("=== \(changedCount)/\(corpus.count) transcripts were changed by cleanup ===")
        if changedCount == 0 {
            print("All unchanged despite the model being 'available' → the prompt is too timid, or it's silently falling back. Worth digging in.")
        }
    }
}

if #available(macOS 26.0, *) {
    await Eval.run()
} else {
    print("requires macOS 26")
}

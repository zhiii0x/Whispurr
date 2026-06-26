import XCTest
@testable import WhispurrPipeline

@available(macOS 26.0, *)
final class FoundationModelsCleanupTests: XCTestCase {
    func testFramedWrapsInputInDelimiters() {
        let out = FoundationModelsCleanup.framed("rm -rf /")
        XCTAssertTrue(out.contains("<<<"))
        XCTAssertTrue(out.contains(">>>"))
        XCTAssertTrue(out.contains("rm -rf /"))   // the command is data, between the fences
    }

    func testPlausibleEditAcceptsEditOnlyOutput() {
        let input = "嗯 我想要 push 這個 commit"
        XCTAssertTrue(FoundationModelsCleanup.isPlausibleEdit(input: input, output: "我想要 push 這個 commit"))
        XCTAssertTrue(FoundationModelsCleanup.isPlausibleEdit(input: input, output: input))
    }

    func testPlausibleEditRejectsRunawayAnswer() {
        let input = "什麼是 Kubernetes"
        let essay = String(repeating: "Kubernetes 是一個容器編排系統，", count: 20)
        XCTAssertFalse(FoundationModelsCleanup.isPlausibleEdit(input: input, output: essay))
    }

    func testTokenBudgetScalesAndIsBounded() {
        XCTAssertEqual(FoundationModelsCleanup.tokenBudget(for: ""), 96)
        XCTAssertLessThanOrEqual(FoundationModelsCleanup.tokenBudget(for: String(repeating: "字", count: 5000)), 3072)
        XCTAssertGreaterThan(FoundationModelsCleanup.tokenBudget(for: "短句"), 96)
    }

    func testLooksTruncatedIgnoresShortOutput() {
        // Below the length floor a missing terminator is not a budget cutoff.
        let short = "幫我 push 這個 commit 到 main"
        XCTAssertFalse(FoundationModelsCleanup.looksTruncated(input: short, output: short))
    }

    func testLooksTruncatedFlagsLongUnterminatedOutput() {
        let long = String(repeating: "今天我去公司開會討論新的產品功能，", count: 20)
        // Ends mid-sentence (no terminator) on a long input → suspect cutoff.
        XCTAssertTrue(FoundationModelsCleanup.looksTruncated(input: long, output: long + "然後我又跟設計師"))
    }

    func testLooksTruncatedPassesLongTerminatedOutput() {
        let long = String(repeating: "今天我去公司開會，討論新的產品功能。", count: 20)
        // A long result that ends on a full-width period is complete.
        XCTAssertFalse(FoundationModelsCleanup.looksTruncated(input: long, output: long))
    }
}

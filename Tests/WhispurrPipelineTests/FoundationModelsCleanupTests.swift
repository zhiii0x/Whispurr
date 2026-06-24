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
        XCTAssertEqual(FoundationModelsCleanup.tokenBudget(for: ""), 64)
        XCTAssertLessThanOrEqual(FoundationModelsCleanup.tokenBudget(for: String(repeating: "字", count: 5000)), 2048)
        XCTAssertGreaterThan(FoundationModelsCleanup.tokenBudget(for: "短句"), 64)
    }
}

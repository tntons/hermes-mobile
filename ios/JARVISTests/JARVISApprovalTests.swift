import XCTest
@testable import JARVIS

final class JARVISApprovalTests: XCTestCase {
    func testApprovalDecisionRequestEncodesOneActionDecision() throws {
        let data = try JSONEncoder().encode(ApprovalDecisionRequest(decision: "approve"))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: String]
        XCTAssertEqual(object?["decision"], "approve")
    }

    func testApprovalRoutesUseMobileBridgeEndpoints() {
        let base = URL(string: "https://jarvis.example.com")!
        XCTAssertEqual(JarvisAPI.approvals.url(base: base).path, "/mobile/approvals")
        XCTAssertEqual(
            JarvisAPI.approvalDecision(id: "approval-1").url(base: base).path,
            "/mobile/approvals/approval-1/decision"
        )
        XCTAssertEqual(JarvisAPI.approvalDecision(id: "approval-1").method, "POST")
    }
}

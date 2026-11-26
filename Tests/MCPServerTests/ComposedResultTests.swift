import MacosUseSDK
import Testing

@testable import mcp_server_macos_use

struct ComposedResultTests {
    @Test func test_merge_keepsPrimaryError() {
        let r = mergeComposedResults(
            primary: ActionResult(primaryActionError: "click failed"),
            additional: [ActionResult(primaryActionError: "type failed")],
            final: ActionResult())
        #expect(r.primaryActionError == "click failed")
    }

    @Test func test_merge_surfacesAdditionalError() {
        let r = mergeComposedResults(
            primary: ActionResult(),
            additional: [ActionResult(), ActionResult(primaryActionError: "type failed")],
            final: ActionResult(traversalAfterError: "t"))
        #expect(r.primaryActionError == "type failed")
        #expect(r.traversalAfterError == "t")
    }

    @Test func test_merge_takesAfterTraversalFromFinal() {
        let after = response([element(#"{"role":"AXButton","text":"Sent"}"#)])
        let r = mergeComposedResults(
            primary: ActionResult(traversalPid: 42),
            additional: [],
            final: ActionResult(traversalAfter: after))
        #expect(r.traversalPid == 42)
        #expect(r.traversalAfter?.elements.first?.text == "Sent")
        #expect(r.primaryActionError == nil)
    }
}

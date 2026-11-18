import Foundation
import Testing
import MacosUseSDK
@testable import mcp_server_macos_use

// SDK types have no public memberwise init, so tests build them from JSON.
func element(_ json: String) -> ElementData {
    try! JSONDecoder().decode(ElementData.self, from: Data(json.utf8))
}

func response(_ elements: [ElementData]) -> ResponseData {
    let stats = #"{"count":0,"excluded_count":0,"excluded_non_interactable":0,"excluded_no_text":0,"with_text_count":0,"without_text_count":0,"visible_elements_count":0,"truncated":false,"role_counts":{}}"#
    let els = String(data: try! JSONEncoder().encode(elements), encoding: .utf8)!
    let json = #"{"app_name":"T","elements":\#(els),"stats":\#(stats),"processing_time_seconds":"0"}"#
    return try! JSONDecoder().decode(ResponseData.self, from: Data(json.utf8))
}

struct ResponseFilteringTests {
    @Test func test_findTextForElement_usesChildTextInsideBounds() {
        let row = element(#"{"role":"AXRow","x":0,"y":0,"width":100,"height":20}"#)
        let child = element(#"{"role":"AXStaticText","text":"Inbox","x":5,"y":5,"width":40,"height":10}"#)
        #expect(findTextForElement(row, in: response([row, child])) == "Inbox")
    }

    @Test func test_isStructuralNoise_keepsRowsWithText() {
        #expect(isStructuralNoise("AXRow", text: nil))
        #expect(!isStructuralNoise("AXRow", text: "Inbox"))
        #expect(!isStructuralNoise("AXButton", text: nil))
    }

    @Test func test_buildToolResponse_dropsScrollBarAndCoordinateOnlyChanges() throws {
        let scrollBar = element(#"{"role":"AXScrollBar","x":0,"y":0,"width":10,"height":100}"#)
        let ok = element(#"{"role":"AXButton","text":"OK","x":20,"y":20,"width":40,"height":20}"#)
        let movedBefore = element(#"{"role":"AXButton","text":"Move","x":0,"y":50,"width":40,"height":20}"#)
        let movedAfter = element(#"{"role":"AXButton","text":"Move","x":5,"y":50,"width":40,"height":20}"#)
        let diffJSON = """
        {"added":[\(enc(scrollBar)),\(enc(ok))],"removed":[],
         "modified":[{"before":\(enc(movedBefore)),"after":\(enc(movedAfter)),
           "changes":[{"attributeName":"x","oldValue":"0","newValue":"5"}]}]}
        """
        let diff = try JSONDecoder().decode(TraversalDiff.self, from: Data(diffJSON.utf8))
        let result = ActionResult(traversalBefore: response([movedBefore]),
                                  traversalAfter: response([scrollBar, ok, movedAfter]),
                                  traversalDiff: diff)
        let toolResponse = buildToolResponse(result, hasDiff: true)
        #expect(toolResponse.diff?.added.map(\.text) == ["OK"])
        #expect(toolResponse.diff?.modified.isEmpty == true)
    }

    private func enc(_ e: ElementData) -> String {
        String(data: try! JSONEncoder().encode(e), encoding: .utf8)!
    }
}

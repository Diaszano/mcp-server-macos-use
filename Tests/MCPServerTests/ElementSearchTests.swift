import Testing

@testable import mcp_server_macos_use

struct ElementSearchTests {
    private func el(_ role: String, _ text: String, visible: Bool = true) -> EnrichedElementData {
        EnrichedElementData(role: role, text: text, x: 10, y: 10, width: 10, height: 10, in_viewport: visible)
    }

    @Test func test_rank_prefersExactOverSubstring() {
        let els = [el("AXButton", "Autosave"), el("AXButton", "Save")]
        #expect(rankElementMatches(els, search: "save", role: nil).first?.text == "Save")
    }

    @Test func test_rank_prefersVisible() {
        let els = [el("AXButton", "Save", visible: false), el("AXButton", "Save", visible: true)]
        #expect(rankElementMatches(els, search: "Save", role: nil).first?.in_viewport == true)
    }

    @Test func test_rank_prefersVisiblePartialOverHiddenExact() {
        let els = [el("AXButton", "Save", visible: false), el("AXButton", "Save As…", visible: true)]
        #expect(rankElementMatches(els, search: "Save", role: nil).first?.text == "Save As…")
    }

    @Test func test_rank_respectsRoleAndReturnsEmpty() {
        #expect(rankElementMatches([el("AXStaticText", "Save")], search: "Save", role: "AXButton").isEmpty)
    }

    @Test func test_rank_skipsZeroSizedElements() {
        var hidden = el("AXButton", "Save")
        hidden.width = 0
        #expect(rankElementMatches([hidden], search: "Save", role: nil).isEmpty)
    }
}

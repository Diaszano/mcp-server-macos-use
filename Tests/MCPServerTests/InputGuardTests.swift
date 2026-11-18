import Testing
@testable import mcp_server_macos_use

struct InputGuardTests {
    @Test func test_overlayMessage_offersEscOnlyWhenTapActive() {
        #expect(InputGuard.overlayMessage("AI: Typing in app…", tapActive: true) == "AI: Typing in app… — press Esc to cancel")
        #expect(InputGuard.overlayMessage("AI: Typing in app…", tapActive: false) == "AI: Typing in app…")
    }
}

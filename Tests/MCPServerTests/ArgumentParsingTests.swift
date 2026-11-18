import CoreGraphics
import MCP
import Testing
@testable import mcp_server_macos_use

struct ArgumentParsingTests {
    @Test func test_hitPoint_centersWhenSizeGiven() throws {
        let args: [String: Value] = ["x": 10, "y": 20, "width": 100, "height": 40]
        #expect(try hitPoint(from: args) == CGPoint(x: 60, y: 40))
    }

    @Test func test_hitPoint_rawWhenNoSize() throws {
        let args: [String: Value] = ["x": "10", "y": 20.0]
        #expect(try hitPoint(from: args) == CGPoint(x: 10, y: 20))
    }

    @Test func test_hitPoint_throwsWithoutY() {
        #expect(throws: MCPError.self) { try hitPoint(from: ["x": 10]) }
    }

    @Test func test_optionalPoint_defaultsToZero() {
        #expect(optionalPoint(from: ["x": 12.7]) == (x: 12, y: 0))
    }

    @Test func test_getRequiredInt_rejectsMissing() {
        #expect(throws: MCPError.self) { try getRequiredInt(from: [:], key: "pid") }
    }
}

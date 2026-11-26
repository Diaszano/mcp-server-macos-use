import Foundation
import Testing

@testable import mcp_server_macos_use

struct OutputDirectoryTests {
    private func makeTempDir() throws -> String {
        let dir = (NSTemporaryDirectory() as NSString).appendingPathComponent("mcp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func test_prune_removesOnlyOldResponseFiles() throws {
        let fm = FileManager.default
        let dir = try makeTempDir()
        defer { try? fm.removeItem(atPath: dir) }
        let now = Date()
        let old = now.addingTimeInterval(-2 * 86_400)
        for (name, date) in [("old.txt", old), ("old.png", old), ("new.txt", now), ("keep.json", old)] {
            let path = (dir as NSString).appendingPathComponent(name)
            fm.createFile(atPath: path, contents: Data())
            try fm.setAttributes([.modificationDate: date], ofItemAtPath: path)
        }
        pruneResponseFiles(in: dir, olderThan: 86_400, now: now)
        #expect(Set(try fm.contentsOfDirectory(atPath: dir)) == ["new.txt", "keep.json"])
    }

    @Test func test_prepareOutputDirectory_setsOwnerOnlyPermissions() throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: parent) }
        let dir = (parent as NSString).appendingPathComponent("macos-use")
        try prepareOutputDirectory(dir)
        let perms = try FileManager.default.attributesOfItem(atPath: dir)[.posixPermissions] as? Int
        #expect(perms == 0o700)
    }

    @Test func test_prepareOutputDirectory_tightensExistingDirectory() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir)
        try prepareOutputDirectory(dir)
        let perms = try FileManager.default.attributesOfItem(atPath: dir)[.posixPermissions] as? Int
        #expect(perms == 0o700)
    }

    @Test func test_prepareOutputDirectory_rejectsRegularFile() throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: parent) }
        let path = (parent as NSString).appendingPathComponent("macos-use")
        FileManager.default.createFile(atPath: path, contents: Data())
        #expect(throws: (any Error).self) { try prepareOutputDirectory(path) }
    }

    @Test func test_prepareOutputDirectory_rejectsSymlink() throws {
        let parent = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: parent) }
        let target = (parent as NSString).appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: false)
        let path = (parent as NSString).appendingPathComponent("macos-use")
        try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target)
        #expect(throws: (any Error).self) { try prepareOutputDirectory(path) }
    }
}

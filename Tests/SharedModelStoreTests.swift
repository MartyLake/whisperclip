import XCTest
import Darwin
@testable import WhisperClip

final class SharedModelStoreTests: XCTestCase {
    func testPrepareCreatesLayoutAndInheritableStaffACL() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SharedModelStore(root: root)

        XCTAssertEqual(try store.prepare(), root)
        for path in ["models", "FluidAudio", ".locks"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
        }
        guard let acl = acl_get_file(root.path, ACL_TYPE_EXTENDED) else {
            return XCTFail("Expected an extended ACL on the model root")
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var length: ssize_t = 0
        guard let text = acl_to_text(acl, &length) else { return XCTFail("Expected readable ACL text") }
        defer { acl_free(text) }
        let aclText = String(cString: text)
        XCTAssertTrue(aclText.contains(":staff:20:"), aclText)
        XCTAssertTrue(aclText.contains("file_inherit"))
        XCTAssertTrue(aclText.contains("directory_inherit"))
    }

    func testPrepareIsIdempotent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SharedModelStore(root: root)

        try store.prepare()
        let before = try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        try store.prepare()
        let after = try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        XCTAssertEqual(before, true)
        XCTAssertEqual(after, true)
    }

    func testRepairPermissionsAddsACLToMovedInFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let store = SharedModelStore(root: root)
        try store.prepare()
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let source = outside.appendingPathComponent("moved.model")
        let destination = root.appendingPathComponent("models/moved.model")
        try Data([1, 2, 3]).write(to: source)
        try FileManager.default.moveItem(at: source, to: destination)

        XCTAssertEqual(try store.repairPermissions(at: destination), 1)
        guard let acl = acl_get_file(destination.path, ACL_TYPE_EXTENDED) else {
            return XCTFail("Expected an ACL on the moved file")
        }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var length: ssize_t = 0
        guard let text = acl_to_text(acl, &length) else { return XCTFail("Expected readable ACL text") }
        defer { acl_free(text) }
        XCTAssertTrue(String(cString: text).contains(":staff:20:"))
    }

    func testExclusiveLockWaitsForFirstOwner() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SharedModelStore(root: root)
        let firstHasLock = expectation(description: "first lock acquired")
        let secondHasLock = expectation(description: "second lock acquired after first releases")
        let first = Task {
            try await store.withExclusiveLock(model: "test-model", timeout: .seconds(3)) {
                firstHasLock.fulfill()
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        await fulfillment(of: [firstHasLock], timeout: 1)
        let second = Task {
            try await store.withExclusiveLock(model: "test-model", timeout: .seconds(3)) {
                secondHasLock.fulfill()
            }
        }
        await fulfillment(of: [secondHasLock], timeout: 3)
        try await first.value
        try await second.value
    }

    func testExclusiveLockTimesOut() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SharedModelStore(root: root)
        let started = expectation(description: "first lock acquired")
        let first = Task {
            try await store.withExclusiveLock(model: "timeout-model", timeout: .seconds(2)) {
                started.fulfill()
                try await Task.sleep(for: .seconds(1))
            }
        }
        await fulfillment(of: [started], timeout: 1)
        do {
            try await store.withExclusiveLock(model: "timeout-model", timeout: .milliseconds(100)) { }
            XCTFail("Expected lock timeout")
        } catch let error as SharedModelStoreError {
            guard case .lockTimeout = error else { return XCTFail("Unexpected error: \(error)") }
        }
        try await first.value
    }
}

import XCTest
import Darwin
@testable import WhisperClip

final class ModelMigrationTests: XCTestCase {
    func testMovesWhenSharedModelIsMissingAndRepairsPermissions() async throws {
        let (base, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("old/model", isDirectory: true)
        let destination = store.root.appendingPathComponent("models/model", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data([1]).write(to: source.appendingPathComponent("weights.bin"))

        let action = try await ModelMigration.migrateItem(
            source: source, destination: destination, lock: "model", store: store,
            destinationIsComplete: { _ in false })

        XCTAssertEqual(action, .moved)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("weights.bin").path))
        guard let acl = acl_get_file(destination.appendingPathComponent("weights.bin").path, ACL_TYPE_EXTENDED) else {
            return XCTFail("Expected repaired permissions on the moved model file")
        }
        acl_free(UnsafeMutableRawPointer(acl))
    }

    func testRemovesLocalDuplicateOnlyWhenSharedCopyIsComplete() async throws {
        let (base, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("old/model", isDirectory: true)
        let destination = store.root.appendingPathComponent("models/model", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let action = try await ModelMigration.migrateItem(
            source: source, destination: destination, lock: "model", store: store,
            destinationIsComplete: { _ in true })

        XCTAssertEqual(action, .removedDuplicate)
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testLeavesBothCopiesWhenSharedCopyIsIncomplete() async throws {
        let (base, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("old/model", isDirectory: true)
        let destination = store.root.appendingPathComponent("models/model", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let action = try await ModelMigration.migrateItem(
            source: source, destination: destination, lock: "model", store: store,
            destinationIsComplete: { _ in false })

        XCTAssertEqual(action, .leftIncomplete)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testSecondMigrationIsIdempotent() async throws {
        let (base, store) = try makeStore()
        defer { try? FileManager.default.removeItem(at: base) }
        let source = base.appendingPathComponent("old/model", isDirectory: true)
        let destination = store.root.appendingPathComponent("models/model", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data([1]).write(to: source.appendingPathComponent("weights.bin"))

        let first = try await ModelMigration.migrateItem(source: source, destination: destination, lock: "model", store: store, destinationIsComplete: { _ in false })
        let second = try await ModelMigration.migrateItem(source: source, destination: destination, lock: "model", store: store, destinationIsComplete: { _ in false })

        XCTAssertEqual(first, .moved)
        XCTAssertNil(second)
    }

    private func makeStore() throws -> (URL, SharedModelStore) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let store = SharedModelStore(root: base.appendingPathComponent("shared", isDirectory: true))
        try store.prepare()
        return (base, store)
    }
}

extension ModelMigration.ItemAction: Equatable {}

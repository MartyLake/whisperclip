import XCTest
@testable import WhisperClip

final class ModelPathsTests: XCTestCase {
    func testResolverUsesInjectedSharedRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SharedModelStore(root: root)

        XCTAssertEqual(ModelLocations.resolve(sharedStore: store, fallback: root.appendingPathComponent("fallback")), root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("models").path))
    }

    func testResolverFallsBackWhenSharedDirectoryIsOwnedByAnotherUser() {
        let fallback = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SharedModelStore(root: URL(fileURLWithPath: "/System/Library", isDirectory: true))

        XCTAssertEqual(ModelLocations.resolve(sharedStore: store, fallback: fallback), fallback)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fallback.path))
    }

    func testModelDirectoriesResolveUnderSharedRootAndKeepTokenizerCachePerUser() {
        let whisperPath = ModelStorage.shared.getModelDir(modelRepo: WhisperKitRepo, modelName: CurrentSTTModelName)
        let parakeetPath = LocalParakeet.getModelsDirectory()
        let eouPath = LocalParakeet.getStreamingModelsDirectory()
        let tokenizerBase = GenericHelper.getAppSupportDirectory().appendingPathComponent("tokenizers", isDirectory: true)

        XCTAssertTrue(whisperPath.path.hasPrefix(ModelLocations.root.appendingPathComponent("models").path))
        XCTAssertTrue(parakeetPath.path.hasPrefix(ModelLocations.fluidAudio.path))
        XCTAssertTrue(eouPath.path.hasPrefix(ModelLocations.fluidAudio.path))
        XCTAssertFalse(tokenizerBase.path.hasPrefix(ModelLocations.root.path))
    }
}

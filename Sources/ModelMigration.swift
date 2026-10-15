import Foundation
import FluidAudio

/// Moves this account's legacy model caches into machine-wide storage once per launch.
enum ModelMigration {
    enum ItemAction { case moved, removedDuplicate, leftIncomplete }
    private actor LaunchGate {
        private var task: Task<Void, Never>?

        func run() async {
            if task == nil {
                task = Task.detached(priority: .utility) { await ModelMigration.performMigration() }
            }
            await task?.value
        }
    }

    private static let launchGate = LaunchGate()

    static func runAtLaunch() async { await launchGate.run() }

    static func migrate() async {
        await runAtLaunch()
    }

    private static func performMigration() async {
        guard ModelLocations.isShared else { return }
        let fm = FileManager.default
        let appSupport = GenericHelper.getAppSupportDirectory()
        let oldModels = appSupport.appendingPathComponent("models", isDirectory: true)
        let sharedModels = ModelLocations.root.appendingPathComponent("models", isDirectory: true)
        let oldFluid = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models", isDirectory: true)
        let sharedFluid = ModelLocations.fluidAudio

        var pairs: [(source: URL, destination: URL, lock: String, isComplete: (URL) -> Bool)] = []
        for modelName in WhisperKitModelNames {
            let source = oldModels.appendingPathComponent(WhisperKitRepo).appendingPathComponent(modelName, isDirectory: true)
            let destination = sharedModels.appendingPathComponent(WhisperKitRepo).appendingPathComponent(modelName, isDirectory: true)
            let checkComplete: (URL) -> Bool = { _ in
                ModelStorage.shared.modelExists(modelRepo: WhisperKitRepo, modelName: modelName)
            }
            pairs.append((source: source, destination: destination, lock: "\(WhisperKitRepo)/\(modelName)", isComplete: checkComplete))
        }
        for modelName in TextLLMModelNames {
            let repo = "mlx-community/\(modelName)"
            let source = oldModels.appendingPathComponent(repo, isDirectory: true)
            let destination = sharedModels.appendingPathComponent(repo, isDirectory: true)
            let checkComplete: (URL) -> Bool = { _ in ModelStorage.shared.modelExists(modelRepo: repo, modelName: "") }
            pairs.append((source: source, destination: destination, lock: repo, isComplete: checkComplete))
        }
        let parakeetRepo = Repo.parakeetV3
        pairs.append((source: oldFluid.appendingPathComponent(parakeetRepo.folderName, isDirectory: true),
                      destination: sharedFluid.appendingPathComponent(parakeetRepo.folderName, isDirectory: true),
                      lock: "parakeet-shared-models", isComplete: { AsrModels.modelsExist(at: $0) }))
        for repo in [Repo.nemotron3Diarization, Repo.campPlus] {
            let source = oldFluid.appendingPathComponent(repo.folderName, isDirectory: true)
            let destination = sharedFluid.appendingPathComponent(repo.folderName, isDirectory: true)
            let lock = repo == .campPlus ? "campplus" : "nemotron3"
            let checkComplete: (URL) -> Bool
            if repo == .campPlus {
                checkComplete = { CampPlusModels.modelsExist(at: $0) }
            } else {
                checkComplete = { _ in ModelStorage.shared.nemotron3ModelsExist(for: SettingsStore.shared.nemotron3Preset) }
            }
            pairs.append((source: source, destination: destination, lock: lock, isComplete: checkComplete))
        }
        let oldEOU = oldFluid.appendingPathComponent(Repo.parakeetEou160.folderName, isDirectory: true)
        let sharedEOU = sharedFluid.appendingPathComponent(Repo.parakeetEou160.folderName, isDirectory: true)
        let eouCheck: (URL) -> Bool = { directory in
            ModelNames.ParakeetEOU.requiredModels.allSatisfy {
                fm.fileExists(atPath: directory.appendingPathComponent($0).path)
            }
        }
        pairs.append((source: oldEOU, destination: sharedEOU, lock: "parakeet-shared-models", isComplete: eouCheck))

        for pair in pairs where fm.fileExists(atPath: pair.source.path) {
            do {
                let action = try await migrateItem(
                    source: pair.source,
                    destination: pair.destination,
                    lock: pair.lock,
                    store: .shared,
                    destinationIsComplete: pair.isComplete)
                switch action {
                case .moved:
                    Logger.log("Migrated a local model cache (\(GenericHelper.formatSize(size: GenericHelper.folderSize(folder: pair.destination))))", log: Logger.general)
                case .removedDuplicate:
                    Logger.log("Removed a duplicate local model cache", log: Logger.general)
                case .leftIncomplete:
                    Logger.log("Kept local model cache because the shared copy is incomplete", log: Logger.general)
                case nil:
                    break
                }
            } catch {
                let detail = GenericHelper.logSensitiveData() ? ": \(error)" : ""
                Logger.log("Model cache migration failed\(detail)", log: Logger.general, type: .error)
            }
        }
    }

    @discardableResult
    static func migrateItem(
        source: URL,
        destination: URL,
        lock: String,
        store: SharedModelStore,
        destinationIsComplete: @escaping (URL) -> Bool
    ) async throws -> ItemAction? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { return nil }
        return try await store.withExclusiveLock(model: lock) {
            if !fm.fileExists(atPath: destination.path) {
                try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: source, to: destination)
                _ = try store.repairPermissions(at: destination)
                return .moved
            }
            if destinationIsComplete(destination) {
                try fm.removeItem(at: source)
                return .removedDuplicate
            }
            return .leftIncomplete
        }
    }
}

import Foundation
import FluidAudio

class LocalParakeet {
    private static let managerCache = ManagerCache()
    private static let streamingChunkSize: StreamingChunkSize = .ms160
    
    /// Get the directory where Parakeet models are stored
    static func getModelsDirectory() -> URL {
        return ModelLocations.fluidAudio.appendingPathComponent(Repo.parakeetV3.folderName, isDirectory: true)
    }

    /// Get the base directory where streaming Parakeet EOU models are stored
    static func getStreamingModelsBaseDirectory() -> URL {
        return ModelLocations.fluidAudio
    }

    static func getStreamingModelsRootDirectory() -> URL {
        getStreamingModelsBaseDirectory()
            .appendingPathComponent(Repo.parakeetEou160.folderName, isDirectory: true)
    }

    /// Get the directory where the configured streaming chunk-size models are stored
    static func getStreamingModelsDirectory(
        chunkSize _: StreamingChunkSize = streamingChunkSize
    ) -> URL {
        getStreamingModelsRootDirectory()
    }
    
    /// Check if Parakeet models are downloaded
    static func modelsExist() -> Bool {
        return AsrModels.modelsExist(at: getModelsDirectory())
    }

    /// Check if streaming Parakeet EOU models are downloaded
    static func streamingModelsExist(
        chunkSize: StreamingChunkSize = streamingChunkSize
    ) -> Bool {
        let directory = getStreamingModelsDirectory(chunkSize: chunkSize)
        let requiredFiles = ModelNames.ParakeetEOU.requiredModels
        return requiredFiles.allSatisfy { fileName in
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(fileName).path
            )
        }
    }
    
    /// Get the size of downloaded Parakeet models
    static func getModelsSize() -> Int64 {
        let directory = getModelsDirectory()
        return GenericHelper.folderSize(folder: directory)
    }

    /// Get the size of downloaded streaming Parakeet EOU models
    static func getStreamingModelsSize() -> Int64 {
        GenericHelper.folderSize(folder: getStreamingModelsRootDirectory())
    }
    
    /// Delete downloaded Parakeet models
    static func deleteModels() throws {
        let directory = getModelsDirectory()
        if FileManager.default.fileExists(atPath: directory.path) {
            try ModelLocations.store.withExclusiveLockSync(model: "parakeet-shared-models") {
                try FileManager.default.removeItem(at: directory)
            }
            if GenericHelper.logSensitiveData() {
                Logger.log("Parakeet models deleted from \(directory.path)", log: Logger.general)
            }
        }
        managerCache.value = nil
    }

    /// Delete downloaded streaming Parakeet EOU models
    static func deleteStreamingModels() throws {
        let directory = getStreamingModelsRootDirectory()
        if FileManager.default.fileExists(atPath: directory.path) {
            try ModelLocations.store.withExclusiveLockSync(model: "parakeet-shared-models") {
                try FileManager.default.removeItem(at: directory)
            }
            if GenericHelper.logSensitiveData() {
                Logger.log("Parakeet streaming models deleted from \(directory.path)", log: Logger.general)
            }
        }
    }
    
    /// Download Parakeet models with progress tracking
    /// Progress milestones:
    /// offline download/load/init = 0-70%
    /// streaming download = 70-100%
    static func downloadModels(progress: @escaping (Double) -> Void) async throws {
        await ModelMigration.runAtLaunch()
        Logger.log("Downloading Parakeet models...", log: Logger.general)
        
        // Check disk space first
        let freeSpace = GenericHelper.getFreeDiskSpace(path: ModelLocations.root)
        if freeSpace < MinimalFreeDiskSpace {
            let shouldContinue = await WhisperClip.shared?.showNoEnoughDiskSpaceAlert(freeSpace: freeSpace) ?? false
            if !shouldContinue {
                throw NSError(domain: "LocalParakeet", code: 2, 
                              userInfo: [NSLocalizedDescriptionKey: "Not enough disk space. Required: 20GB, Available: \(GenericHelper.formatSize(size: freeSpace))"])
            }
        }
        
        // Clear any stale cache before downloading
        await clearCache()
        
        progress(0.01)
        
        try await ModelLocations.store.withExclusiveLock(model: "parakeet-shared-models", timeout: .seconds(1800)) {
        do {
            let offlineExists = modelsExist()
            let streamingExists = streamingModelsExist()
            if offlineExists && streamingExists {
                Logger.log("Parakeet models already exist, skipping download", log: Logger.general)
                progress(1.0)
                return
            }
            if !offlineExists {
                // Download models - FluidAudio handles the download internally
                _ = try await AsrModels.download(to: getModelsDirectory(), version: .v3)
                if ModelLocations.isShared { _ = try SharedModelStore.shared.repairPermissions(at: getModelsDirectory()) }
                progress(0.45)

                // Load models to trigger CoreML compilation
                let models = try await AsrModels.load(from: getModelsDirectory(), version: .v3)
                progress(0.65)

                // Initialize the manager to verify everything works
                let manager = AsrManager(config: .default)
                try await manager.loadModels(models)

                // Verify manager is actually available
                guard await manager.isAvailable else {
                    throw NSError(domain: "LocalParakeet", code: 3,
                                  userInfo: [NSLocalizedDescriptionKey: "Parakeet manager initialized but not available"])
                }

                managerCache.value = manager
            }

            progress(max(0.70, offlineExists ? 0.70 : 0.65))

            if !streamingExists {
                try await ModelHub.download(.parakeetEou160, to: getStreamingModelsBaseDirectory())
                if ModelLocations.isShared { _ = try SharedModelStore.shared.repairPermissions(at: getStreamingModelsRootDirectory()) }
            }

            progress(1.0)
            Logger.log("Parakeet models downloaded and loaded successfully", log: Logger.general)
        } catch {
            let message = GenericHelper.logSensitiveData()
                ? "Failed to download Parakeet models: \(error)"
                : "Failed to download Parakeet models"
            Logger.log(message, log: Logger.general, type: .error)
            throw error
        }
        }
    }
    
    /// Load Parakeet model (downloads if needed)
    static func loadModel() async throws -> AsrManager {
        await ModelMigration.runAtLaunch()
        // Validate models exist first
        guard modelsExist() else {
            throw NSError(domain: "LocalParakeet", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Parakeet models not downloaded. Please download them from Setup Guide."])
        }
        
        // Return cached manager if available and valid
        if let manager = managerCache.value, await manager.isAvailable {
            return manager
        }
        
        Logger.log("Loading Parakeet model via FluidAudio", log: Logger.general)

        // Load models (they should already exist at this point)
        let models = try await AsrModels.load(from: getModelsDirectory(), version: .v3)

        // Create and initialize ASR manager
        let config = ASRConfig.default
        let manager = AsrManager(config: config)
        try await manager.loadModels(models)
        
        // Verify manager is actually available
        guard await manager.isAvailable else {
            await clearCache()
            throw NSError(domain: "LocalParakeet", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Parakeet manager initialized but not available"])
        }
        
        managerCache.value = manager

        Logger.log("Parakeet model loaded successfully", log: Logger.general)
        return manager
    }
    
    /// Clear cached manager (useful when deleting models)
    static func clearCache() async {
        managerCache.value = nil
    }
}

/// NSLock serializes the shared actor reference while keeping synchronous deletion APIs intact.
private final class ManagerCache: @unchecked Sendable {
    private let lock = NSLock()
    private var manager: AsrManager?

    var value: AsrManager? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return manager
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            manager = newValue
        }
    }
}

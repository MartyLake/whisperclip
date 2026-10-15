import Foundation
import FluidAudio

protocol SpeakerEmbedder: Sendable {
    func embed(_ samples: [Float]) async throws -> [Float]
}

func cosine(_ a: [Float], _ b: [Float]) -> Float {
    guard !a.isEmpty, a.count == b.count,
          a.allSatisfy({ $0.isFinite }), b.allSatisfy({ $0.isFinite }) else { return 0 }
    let norm = sqrt(a.reduce(0) { $0 + $1 * $1 } * b.reduce(0) { $0 + $1 * $1 })
    guard norm > 0, norm.isFinite else { return 0 }
    return zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } / norm
}

struct CampPlusSpeakerEmbedder: SpeakerEmbedder {
    private let model: CampPlusEmbedder

    static func load() async throws -> Self {
        await ModelMigration.runAtLaunch()
        // FluidAudio's informational model-loader messages include local paths.
        AppLogger.minimumLevel = GenericHelper.logSensitiveData() ? .debug : .warning
        let directory = ModelLocations.fluidAudio.appendingPathComponent(Repo.campPlus.folderName, isDirectory: true)
        try await ModelLocations.store.withExclusiveLock(model: "campplus") {
            if !CampPlusModels.modelsExist(at: directory) {
                try await ModelHub.download(.campPlus, to: ModelLocations.fluidAudio)
                if ModelLocations.isShared { _ = try SharedModelStore.shared.repairPermissions(at: directory) }
            }
        }
        return Self(model: CampPlusEmbedder(models: try CampPlusModels.load(from: directory)))
    }

    func embed(_ samples: [Float]) async throws -> [Float] {
        try await model.embed(audio: samples)
    }
}

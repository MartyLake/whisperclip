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
        // FluidAudio's informational model-loader messages include local paths.
        AppLogger.minimumLevel = GenericHelper.logSensitiveData() ? .debug : .warning
        // FluidAudio/Models/campplus-coreml; uses the dependency's cache layout.
        return Self(model: try await CampPlusEmbedder.load())
    }

    func embed(_ samples: [Float]) async throws -> [Float] {
        try await model.embed(audio: samples)
    }
}

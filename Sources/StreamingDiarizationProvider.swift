import Foundation
import FluidAudio

struct StreamingDiarizationChunk: Sendable {
    let probabilities: [Float]
    let frameCount: Int
    let numSpeakers: Int
}

protocol StreamingDiarizationProvider: Sendable {
    var latencySeconds: Double { get }
    func append(_ samples: [Float]) throws
    func process() throws -> [StreamingDiarizationChunk]
    func finish() throws -> [StreamingDiarizationChunk]
    func reset()
}

enum Nemotron3Preset: String, CaseIterable, Identifiable, Sendable {
    case fast
    case fast32
    case fast128

    static let defaultPreset: Self = .fast32
    var id: String { rawValue }
    var config: Nemotron3Config {
        switch self {
        case .fast: .fast
        case .fast32: .fast32
        case .fast128: .fast128
        }
    }
    var displayName: String { rawValue }
    var latencyDescription: String {
        switch self {
        case .fast: "about 1 s"
        case .fast32: "about 3 s"
        case .fast128: "about 11 s"
        }
    }
    var downloadSizeDescription: String { "about 199 MB" }
    var latencySeconds: Double { config.latencySeconds }
}

enum StreamingDiarizationError: LocalizedError {
    case streamFinished

    var errorDescription: String? {
        switch self {
        case .streamFinished: "The diarization stream has finished. Reset it before adding audio."
        }
    }
}

/// Used by one SpeakerBufferManager actor only. Nemotron3Diarizer has mutable streaming
/// state and is not thread-safe; the actor is the exclusive owner for its full lifetime.
final class Nemotron3DiarizationProvider: StreamingDiarizationProvider, @unchecked Sendable {
    private let diarizer: Nemotron3Diarizer
    private let streamLatency: Double
    private var isFinished = false

    init(preset: Nemotron3Preset, models: Nemotron3Models) {
        diarizer = Nemotron3Diarizer(config: preset.config, models: models)
        streamLatency = preset.latencySeconds
    }

    var latencySeconds: Double { streamLatency }

    func append(_ samples: [Float]) throws {
        guard !isFinished else { throw StreamingDiarizationError.streamFinished }
        diarizer.appendAudio(samples)
    }

    func process() throws -> [StreamingDiarizationChunk] {
        try diarizer.processBufferedAudio().map(Self.convert)
    }

    func finish() throws -> [StreamingDiarizationChunk] {
        guard !isFinished else { return [] }
        isFinished = true
        return try diarizer.finishStream().map(Self.convert)
    }

    func reset() {
        diarizer.reset()
        isFinished = false
    }

    private static func convert(_ chunk: Nemotron3ChunkResult) -> StreamingDiarizationChunk {
        StreamingDiarizationChunk(probabilities: chunk.probabilities,
                                  frameCount: chunk.frameCount,
                                  numSpeakers: chunk.numSpeakers)
    }
}

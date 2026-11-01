import Foundation
@testable import WhisperClip

final class MockStreamingDiarizationProvider: StreamingDiarizationProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var processResults: [[StreamingDiarizationChunk]]
    private var finishResults: [StreamingDiarizationChunk]
    private(set) var appendedSamples = 0
    private(set) var processCallCount = 0
    var latencySeconds: Double = 2.88

    init(processResults: [[StreamingDiarizationChunk]] = [], finishResults: [StreamingDiarizationChunk] = []) {
        self.processResults = processResults
        self.finishResults = finishResults
    }

    func append(_ samples: [Float]) throws {
        lock.lock(); defer { lock.unlock() }
        appendedSamples += samples.count
    }

    func process() throws -> [StreamingDiarizationChunk] {
        lock.lock(); defer { lock.unlock() }
        processCallCount += 1
        guard !processResults.isEmpty else { return [] }
        return processResults.removeFirst()
    }

    func finish() throws -> [StreamingDiarizationChunk] {
        lock.lock(); defer { lock.unlock() }
        return finishResults
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        appendedSamples = 0
        processCallCount = 0
    }

    func appendedSampleCount() -> Int {
        lock.lock(); defer { lock.unlock() }
        return appendedSamples
    }
}

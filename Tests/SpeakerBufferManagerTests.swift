import XCTest
@testable import WhisperClip

final class SpeakerBufferManagerTests: XCTestCase {
    private actor BufferCollector {
        var buffers: [ClosedSpeakerBuffer] = []
        func append(_ buffer: ClosedSpeakerBuffer) { buffers.append(buffer) }
    }

    func testEmitsStableLabeledTurnAfterTimelineClosesIt() async throws {
        let speech = StreamingDiarizationChunk(probabilities: Array(repeating: 0.9, count: 60),
                                                frameCount: 60, numSpeakers: 1)
        let silence = StreamingDiarizationChunk(probabilities: Array(repeating: 0, count: 30),
                                                 frameCount: 30, numSpeakers: 1)
        let combined = StreamingDiarizationChunk(
            probabilities: speech.probabilities + silence.probabilities, frameCount: 90, numSpeakers: 1)
        let provider = MockStreamingDiarizationProvider(processResults: [[combined]])
        let manager = SpeakerBufferManager(provider: provider, pollingInterval: 10_000_000)
        let collector = BufferCollector()
        let consumer = Task {
            for await buffer in manager.buffers {
                await collector.append(buffer)
            }
        }
        await manager.onAudioBatch(Array(repeating: 0.1, count: 14_400), atTime: 0)
        await manager.start()
        try await Task.sleep(nanoseconds: 100_000_000)
        await manager.stop()
        _ = await consumer.value
        let buffers = await collector.buffers
        XCTAssertEqual(buffers.count, 1)
        XCTAssertEqual(buffers.first?.speakerLabel, "Speaker 1")
        XCTAssertEqual(buffers.first?.samples.count, 9_600)
        let timeline = await manager.timelineSnapshot()
        XCTAssertEqual(timeline.coveredSeconds, 0.9, accuracy: 0.001)
        XCTAssertEqual(timeline.turns(from: 0, to: 0.9).count, 1)
    }

    func testCaptureGapPadsProviderAndAudioClock() async {
        let provider = MockStreamingDiarizationProvider()
        let manager = SpeakerBufferManager(provider: provider)
        await manager.onAudioBatch(Array(repeating: 0, count: 16_000), atTime: 0)
        await manager.onAudioBatch(Array(repeating: 0, count: 16_000), atTime: 2)
        XCTAssertEqual(provider.appendedSampleCount(), 48_000)
    }

    func testNinetySecondsAreEmittedOnceWithSessionAlignedSamplesAndTimes() async throws {
        let sampleRate = 16_000
        var probabilities: [Float] = []
        probabilities.reserveCapacity(9_000 * 2)
        for frame in 0..<9_000 {
            let speaker = (frame / 1_000) % 2
            probabilities.append(speaker == 0 ? 0.9 : 0.1)
            probabilities.append(speaker == 1 ? 0.9 : 0.1)
        }
        let chunk = StreamingDiarizationChunk(probabilities: probabilities, frameCount: 9_000, numSpeakers: 2)
        let provider = MockStreamingDiarizationProvider(processResults: [[chunk]])
        let manager = SpeakerBufferManager(provider: provider, pollingInterval: 10_000_000)
        let collector = BufferCollector()
        let consumer = Task {
            for await buffer in manager.buffers { await collector.append(buffer) }
        }
        let samples = (0..<90).flatMap { second in
            [Float](repeating: Float(second), count: sampleRate)
        }
        await manager.onAudioBatch(samples, atTime: 0)
        await manager.start()
        try await Task.sleep(nanoseconds: 30_000_000)
        await manager.stop()
        _ = await consumer.value

        let buffers = await collector.buffers
        let emittedSamples = buffers.reduce(0) { $0 + $1.samples.count }
        XCTAssertEqual(emittedSamples, 90 * sampleRate)
        XCTAssertEqual(buffers.count, 9)
        for buffer in buffers {
            XCTAssertEqual(buffer.samples.first, Float(Int(buffer.startTime.rounded())))
        }
    }

    func testStopFlushesProviderTail() async {
        let speech = [Float](repeating: 0.9, count: 60)
        let silence = [Float](repeating: 0, count: 30)
        let tail = StreamingDiarizationChunk(probabilities: speech + silence,
                                             frameCount: 90, numSpeakers: 1)
        let provider = MockStreamingDiarizationProvider(finishResults: [tail])
        let manager = SpeakerBufferManager(provider: provider)
        let collector = BufferCollector()
        let consumer = Task {
            for await buffer in manager.buffers { await collector.append(buffer) }
        }
        await manager.onAudioBatch(Array(repeating: 0.1, count: 14_400), atTime: 0)
        await manager.stop()
        _ = await consumer.value
        let buffers = await collector.buffers
        XCTAssertEqual(buffers.count, 1)
    }
}

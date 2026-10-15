import XCTest
@testable import WhisperClip

final class SpeakerBufferManagerTests: XCTestCase {
    func testCaptureGapPadsProviderClock() async {
        let provider = MockStreamingDiarizationProvider()
        let manager = SpeakerBufferManager(provider: provider)
        let before = await manager.sessionStartTime
        XCTAssertNil(before)
        await manager.onAudioBatch(Array(repeating: 0, count: 16_000), atTime: 5)
        await manager.onAudioBatch(Array(repeating: 0, count: 16_000), atTime: 7)
        XCTAssertEqual(provider.appendedSampleCount(), 48_000)
        let start = await manager.sessionStartTime
        XCTAssertEqual(start, 5)
    }

    func testStopFlushesTimelineWithCaptureOffsetAndWindow() async {
        let tail = StreamingDiarizationChunk(probabilities: Array(repeating: 0.9, count: 500), frameCount: 500, numSpeakers: 1)
        let manager = SpeakerBufferManager(provider: MockStreamingDiarizationProvider(finishResults: [tail]))
        await manager.onAudioBatch(Array(repeating: 0.1, count: 80_000), atTime: 7)
        let before = await manager.timelineView()
        XCTAssertEqual(before.coveredThrough, 7)
        await manager.stop()
        let full = await manager.timelineView()
        let window = await manager.timelineView(from: 10)
        XCTAssertEqual(full.coveredThrough, 12)
        XCTAssertEqual(full.turns(from: 10, to: 12), window.turns(from: 10, to: 12))
        XCTAssertEqual(full.turns(from: 7, to: 12), [SpeakerTurn(slot: 0, startSeconds: 7, endSeconds: 12)])
        XCTAssertLessThan(window.frames.count, full.frames.count)
    }
}

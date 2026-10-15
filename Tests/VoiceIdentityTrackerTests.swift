import XCTest
@testable import WhisperClip

private actor TestSpeakerEmbedder: SpeakerEmbedder {
    private(set) var calls = 0
    func embed(_ samples: [Float]) async throws -> [Float] {
        calls += 1
        return voiceVector(0)
    }
}

final class VoiceIdentityTrackerTests: XCTestCase {
    private func window(seconds: Int, slot: UInt8 = 1) -> SpeakerTimelineWindow {
        SpeakerTimelineWindow(frames: Array(repeating: slot, count: seconds * 100) + Array(repeating: 0, count: 30),
                              startTime: 0, coveredThrough: Double(seconds) + 0.3)
    }

    func testMilestoneMatchOnceAndFinish() async {
        let model = TestSpeakerEmbedder()
        let id = UUID()
        let tracker = VoiceIdentityTracker(embedder: model, profiles: [VoiceProfileVectors(id: id, name: "A", samples: [voiceVector(0)])])
        await tracker.appendAudio(Array(repeating: 1, count: 6 * 16_000), at: 0)
        let events = await tracker.update(timeline: window(seconds: 5))
        XCTAssertEqual(events.count, 1)
        let again = await tracker.update(timeline: window(seconds: 5))
        XCTAssertTrue(again.isEmpty)
        let calls = await model.calls
        XCTAssertEqual(calls, 1)
        let voices = await tracker.finish()
        XCTAssertEqual(voices.first?.profileID, id)
        XCTAssertEqual(voices.first?.label, "A")
        XCTAssertNotNil(voices.first?.embedding)
        let finalCalls = await model.calls
        XCTAssertEqual(finalCalls, 2)
    }

    func testShortSpeechHasNoSavedEmbeddingAndLockPreventsMatch() async {
        let tracker = VoiceIdentityTracker(embedder: TestSpeakerEmbedder(), profiles: [VoiceProfileVectors(id: UUID(), name: "A", samples: [voiceVector(0)])])
        await tracker.lock(slot: 0, profileID: nil, name: "Manual")
        await tracker.appendAudio(Array(repeating: 1, count: 5 * 16_000), at: 0)
        let events = await tracker.update(timeline: window(seconds: 4))
        XCTAssertTrue(events.isEmpty)
        let voices = await tracker.finish()
        XCTAssertEqual(voices.first?.label, "Manual")
        XCTAssertNil(voices.first?.embedding)
    }

    func testGrowingTurnCountsOnceAndEmptyProfiles() async {
        let tracker = VoiceIdentityTracker(embedder: TestSpeakerEmbedder(), profiles: [])
        await tracker.appendAudio(Array(repeating: 1, count: 6 * 16_000), at: 0)
        let open = SpeakerTimelineWindow(frames: Array(repeating: 1, count: 200), startTime: 0, coveredThrough: 2)
        _ = await tracker.update(timeline: open)
        let initial = await tracker.snapshot()
        XCTAssertEqual(initial.first?.speechSeconds, 2)
        let events = await tracker.update(timeline: window(seconds: 5))
        XCTAssertTrue(events.isEmpty)
        let final = await tracker.finish()
        XCTAssertEqual(final.first?.speechSeconds, 5)
        XCTAssertNotNil(final.first?.embedding)
    }
    func testLongTurnAcrossRollingWindowCountsSpeechOnce() async {
        let tracker = VoiceIdentityTracker(embedder: TestSpeakerEmbedder(), profiles: [])
        for second in 0..<45 {
            await tracker.appendAudio(Array(repeating: 1, count: 16_000), at: Double(second))
            let start = max(0, second - 27)
            let timeline = SpeakerTimelineWindow(frames: Array(repeating: 1, count: (second + 1 - start) * 100),
                                                 startTime: Double(start), coveredThrough: Double(second + 1))
            _ = await tracker.update(timeline: timeline)
        }
        let voices = await tracker.finish()
        XCTAssertEqual(voices.first?.speechSeconds, 45)
        XCTAssertNotNil(voices.first?.embedding)
    }

}

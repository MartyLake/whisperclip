import XCTest
@testable import WhisperClip

final class VoiceSampleCollectorTests: XCTestCase {
    func testTrimFallbackDedupAndTotalSpeech() {
        var collector = VoiceSampleCollector()
        collector.appendAudio(Array(repeating: 1, count: 160_000), at: 0)
        let turns = [SpeakerTurn(slot: 0, startSeconds: 0, endSeconds: 2),
                     SpeakerTurn(slot: 0, startSeconds: 3, endSeconds: 3.6),
                     SpeakerTurn(slot: 0, startSeconds: 4, endSeconds: 4.2)]
        collector.consume(turns)
        collector.consume(turns)
        XCTAssertEqual(collector.audio(for: 0).count, 38_400)
        XCTAssertEqual(collector.speechSeconds[0] ?? 0, 2.8, accuracy: 0.001)
    }

    func testRingBoundsAndMilestones() {
        var collector = VoiceSampleCollector()
        collector.appendAudio(Array(repeating: 1, count: 40 * 16_000), at: 0)
        collector.consume([SpeakerTurn(slot: 0, startSeconds: 0, endSeconds: 2)])
        XCTAssertTrue(collector.audio(for: 0).isEmpty)
        for index in 0..<4 {
            let start = Double(10 + index * 5)
            collector.consume([SpeakerTurn(slot: 0, startSeconds: start, endSeconds: start + 4.5)])
            if index == 0 || index == 1 || index == 3 { XCTAssertTrue(collector.readyForEmbedding(slot: 0)) }
            XCTAssertFalse(collector.readyForEmbedding(slot: 0))
        }
        XCTAssertEqual(collector.audio(for: 0).count, 15 * 16_000)
    }

    func testCapPrefersLongPieces() {
        var collector = VoiceSampleCollector()
        collector.appendAudio(Array(repeating: 0.25, count: 30 * 16_000), at: 0)
        collector.consume((0..<10).map { SpeakerTurn(slot: 0, startSeconds: Double($0 * 2), endSeconds: Double($0 * 2 + 2)) })
        collector.appendAudio(Array(repeating: 0.75, count: 5 * 16_000), at: 30)
        collector.consume([SpeakerTurn(slot: 0, startSeconds: 30, endSeconds: 35)])
        XCTAssertEqual(collector.audio(for: 0).count, 15 * 16_000)
        XCTAssertEqual(collector.audio(for: 0).first, 0.75)
    }
    func testFallbackRemovedAfterThreePreferredTurns() {
        var collector = VoiceSampleCollector()
        collector.appendAudio(Array(repeating: 1, count: 10 * 16_000), at: 0)
        collector.consume([SpeakerTurn(slot: 0, startSeconds: 0, endSeconds: 0.8)])
        XCTAssertEqual(collector.audio(for: 0).count, 9_600)
        var turns: [SpeakerTurn] = []
        for index in 0..<3 {
            let start = Double(1 + index * 3)
            turns.append(SpeakerTurn(slot: 0, startSeconds: start, endSeconds: start + 2))
        }
        collector.consume(turns)
        XCTAssertEqual(collector.audio(for: 0).count, 3 * 28_800)
        XCTAssertEqual(collector.speechSeconds[0] ?? 0, 6.8, accuracy: 0.001)
    }

}

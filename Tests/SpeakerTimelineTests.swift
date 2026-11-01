import XCTest
@testable import WhisperClip

final class SpeakerTimelineTests: XCTestCase {
    func testBuildsSlotsAndSilenceFromFrameProbabilities() {
        var timeline = SpeakerTimeline()
        timeline.append(probabilities: [0, 0, 0.1, 0.8, 0.1, 0.9], frameCount: 3, numSpeakers: 2)
        XCTAssertEqual(timeline.coveredSeconds, 0.03, accuracy: 0.0001)
        XCTAssertEqual(timeline.dominantSpeaker(from: 0, to: 0.03), 1)
        XCTAssertEqual(timeline.label(forSlot: 1), "Speaker 2")
    }

    func testOverlapChoosesHighestSlotAndChunkAppendKeepsContiguousTimeline() {
        var timeline = SpeakerTimeline()
        timeline.append(probabilities: Array(repeating: [Float(0.7), 0.7], count: 20).flatMap { $0 },
                        frameCount: 20, numSpeakers: 2)
        timeline.append(probabilities: Array(repeating: [Float(0.7), 0.95], count: 20).flatMap { $0 },
                        frameCount: 20, numSpeakers: 2)
        XCTAssertEqual(timeline.dominantSpeaker(from: 0.2, to: 0.4), 1)
        XCTAssertEqual(timeline.coveredSeconds, 0.4, accuracy: 0.0001)
    }

    func testAlternatingSpeakersKeepSlotLabelsAndTurnBoundaries() {
        var timeline = SpeakerTimeline()
        timeline.append(probabilities: Array(repeating: [0.9, 0.1], count: 30).flatMap { $0 },
                        frameCount: 30, numSpeakers: 2)
        timeline.append(probabilities: Array(repeating: [0.1, 0.9], count: 30).flatMap { $0 },
                        frameCount: 30, numSpeakers: 2)
        let turns = timeline.turns(from: 0, to: 0.6)
        XCTAssertEqual(turns.map(\.label), ["Speaker 1", "Speaker 2"])
        XCTAssertEqual(turns.map(\.slot), [0, 1])
    }

    func testSilenceHasNoDominantSpeakerOrTurn() {
        var timeline = SpeakerTimeline()
        timeline.append(probabilities: Array(repeating: 0, count: 100), frameCount: 50, numSpeakers: 2)
        XCTAssertNil(timeline.dominantSpeaker(from: 0, to: 0.5))
        XCTAssertTrue(timeline.turns(from: 0, to: 0.5).isEmpty)
    }

    func testShortSilenceGapMergesSameSpeakerTurnsAndDropsShortTurns() {
        var timeline = SpeakerTimeline()
        let values = (0..<50).flatMap { index in [Float](repeating: index == 24 ? 0 : 0.9, count: 1) }
        timeline.append(probabilities: values, frameCount: 50, numSpeakers: 1)
        XCTAssertEqual(timeline.turns(from: 0, to: 0.5).count, 1)
    }

    func testDropsTurnsBelowMinimumAndClampsQueriesBeyondCoverage() {
        var timeline = SpeakerTimeline()
        let frames = Array(repeating: [Float(0.9)], count: 10)
            + Array(repeating: [Float(0)], count: 25)
            + Array(repeating: [Float(0.9)], count: 30)
        timeline.append(probabilities: frames.flatMap { $0 }, frameCount: frames.count, numSpeakers: 1)
        let turns = timeline.turns(from: 0, to: 10)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns.first?.startSeconds ?? -1, 0.35, accuracy: 0.0001)
        XCTAssertEqual(timeline.dominantSpeaker(from: 0.35, to: 10), 0)
    }
}

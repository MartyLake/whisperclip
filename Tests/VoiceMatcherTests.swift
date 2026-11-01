import XCTest
@testable import WhisperClip

final class VoiceMatcherTests: XCTestCase {
    func testClearMatchAndEmptyProfiles() {
        let id = UUID()
        let profiles = [VoiceProfileVectors(id: id, name: "A", samples: [[1, 0]])]
        XCTAssertEqual(VoiceMatcher.assign(slots: [0: [1, 0]], profiles: profiles, locked: [:])[0]?.profileID, id)
        XCTAssertTrue(VoiceMatcher.assign(slots: [0: [1, 0]], profiles: [], locked: [:]).isEmpty)
    }

    func testBelowThresholdAndAmbiguousAreRejected() {
        let a = VoiceProfileVectors(id: UUID(), name: "A", samples: [[1, 0]])
        let b = VoiceProfileVectors(id: UUID(), name: "B", samples: [[1, 0.01]])
        XCTAssertTrue(VoiceMatcher.assign(slots: [0: [0, 1]], profiles: [a], locked: [:]).isEmpty)
        XCTAssertTrue(VoiceMatcher.assign(slots: [0: [1, 0]], profiles: [a, b], locked: [:]).isEmpty)
    }

    func testGreedyAndLockedAssignment() {
        let id = UUID()
        let profiles = [VoiceProfileVectors(id: id, name: "A", samples: [[1, 0]])]
        let slots = [0: [Float(1), 0], 1: [Float(1), 0.2]]
        let matches = VoiceMatcher.assign(slots: slots, profiles: profiles, locked: [:])
        XCTAssertEqual(matches.count, 1)
        XCTAssertNotNil(matches[0])
        XCTAssertTrue(VoiceMatcher.assign(slots: slots, profiles: profiles, locked: [1: id]).isEmpty)
    }

    func testCosineValidatesVectors() {
        XCTAssertEqual(cosine([1], [1, 0]), 0)
        XCTAssertEqual(cosine([0, 0], [1, 0]), 0)
        XCTAssertEqual(cosine([.nan], [1]), 0)
        XCTAssertEqual(cosine([2, 0], [3, 0]), 1, accuracy: 0.0001)
    }
}

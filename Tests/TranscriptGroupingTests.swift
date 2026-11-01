import XCTest
@testable import WhisperClip

final class TranscriptGroupingTests: XCTestCase {
    private func row(_ speaker: Speaker = .other, _ start: Double = 0,
                     text: String = "hello", pending: Bool = false) -> MeetingSegment {
        MeetingSegment(speaker: speaker, text: text, startTime: start,
                       endTime: start + 1, isPending: pending)
    }

    func testEmptyInput() {
        XCTAssertTrue(TranscriptGrouping.groups(from: []).isEmpty)
    }

    func testSameSpeakerMergesAndKeepsIdentity() {
        let first = row()
        let groups = TranscriptGrouping.groups(from: [first, row(.other, 2)])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].id, first.id)
        XCTAssertEqual(groups[0].startTime, 0)
        XCTAssertEqual(groups[0].endTime, 3)
    }

    func testMeInterjectionSplitsRemoteTurn() {
        for speaker: Speaker in [.other, .labeled("Speaker 1")] {
            let groups = TranscriptGrouping.groups(from: [row(speaker), row(.me, 2), row(speaker, 4)])
            XCTAssertEqual(groups.map(\.speaker), [speaker, .me, speaker])
            XCTAssertTrue(groups[1].isMe)
        }
    }

    func testDistinctDisplaySpeakersSplit() {
        let speakers: [Speaker] = [.labeled("Speaker 1"), .labeled("Speaker 2"), .other, .unknown]
        XCTAssertEqual(TranscriptGrouping.groups(from: speakers.map { row($0) }).map(\.speaker), speakers)
    }

    func testPendingJoinsRemoteThenSplitsWhenResolved() {
        let first = row(.labeled("Speaker 1"))
        let pending = row(.unknown, 2, pending: true)
        XCTAssertEqual(TranscriptGrouping.groups(from: [first, pending])[0].segments.count, 2)
        pending.speaker = .labeled("Speaker 2")
        pending.isPending = false
        let groups = TranscriptGrouping.groups(from: [first, pending])
        XCTAssertEqual(groups.map(\.id), [first.id, pending.id])
        XCTAssertEqual(groups.map(\.speaker), [.labeled("Speaker 1"), .labeled("Speaker 2")])
    }

    func testPendingAfterMeOpensNeutralGroupAndAdoptsResolvedSpeaker() {
        let pending = row(.other, 2, pending: true)
        let groups = TranscriptGrouping.groups(from: [row(.me), pending])
        XCTAssertEqual(groups.count, 2)
        XCTAssertTrue(groups[1].isPendingSpeaker)
        let resolved = TranscriptGrouping.groups(from: [pending, row(.labeled("Speaker 2"), 4)])
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].speaker, .labeled("Speaker 2"))
        XCTAssertEqual(resolved[0].id, pending.id)
    }

    func testGapBoundaryAndPendingGap() {
        XCTAssertEqual(TranscriptGrouping.groups(from: [row(), row(.other, 31)]).count, 1)
        XCTAssertEqual(TranscriptGrouping.groups(from: [row(), row(.other, 32)]).count, 2)
        XCTAssertEqual(TranscriptGrouping.groups(from: [row(), row(.other, 32, pending: true)]).count, 2)
        XCTAssertEqual(TranscriptGrouping.groups(from: [row(), row(.other, 3)], maxGap: 1).count, 2)
    }

    func testPendingMicStaysMe() {
        let groups = TranscriptGrouping.groups(from: [row(.me), row(.me, 2, pending: true)])
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].isMe)
    }

    func testTypingTailRequiresEmptyPendingLastRow() {
        let pending = row(.other, 2, text: "", pending: true)
        XCTAssertTrue(TranscriptGrouping.groups(from: [row(), pending])[0].hasTypingTail)
        XCTAssertFalse(TranscriptGrouping.groups(from: [pending, row(.other, 4)])[0].hasTypingTail)
        pending.text = "partial"
        XCTAssertFalse(TranscriptGrouping.groups(from: [pending])[0].hasTypingTail)
        pending.text = ""
        pending.isPending = false
        XCTAssertFalse(TranscriptGrouping.groups(from: [pending])[0].hasTypingTail)
    }
}

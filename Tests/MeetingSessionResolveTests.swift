import XCTest
@testable import WhisperClip

@MainActor
final class MeetingSessionResolveTests: XCTestCase {
    func testLabelStoresOriginalExactlyOnce() {
        var saved: [MeetingSegment] = []
        let session = MeetingSession(meetingId: UUID()) { segment, _ in saved.append(segment) }
        let pending = MeetingSegment(speaker: .pending, text: "hello", startTime: 0, endTime: 1, confidence: 0, isPending: true)
        session.addPendingSegment(pending)
        let part = MeetingSegment(speaker: .labeled("Speaker 1"), text: "hello", startTime: 0, endTime: 1, confidence: 0.95)
        session.resolvePendingSegment(id: pending.id, parts: [part])
        session.resolvePendingSegment(id: pending.id, parts: [part])
        XCTAssertEqual(saved.count, 1)
        XCTAssertTrue(saved.first === pending)
        XCTAssertEqual(pending.speaker, .labeled("Speaker 1"))
        XCTAssertFalse(pending.isPending)
    }

    func testSplitReplacesOriginalAndStoresEachPartOnceInTimeOrder() {
        var saved: [MeetingSegment] = []
        let session = MeetingSession(meetingId: UUID()) { segment, _ in saved.append(segment) }
        let pending = MeetingSegment(speaker: .pending, text: "one two", startTime: 0, endTime: 3, confidence: 0, isPending: true)
        let mic = MeetingSegment(speaker: .me, text: "mic", startTime: 1, endTime: 2, confidence: 0, isPending: true)
        session.addPendingSegment(pending)
        session.addPendingSegment(mic)
        let parts = [MeetingSegment(speaker: .labeled("Speaker 1"), text: "one", startTime: 0, endTime: 2, confidence: 0.95),
                     MeetingSegment(speaker: .labeled("Speaker 2"), text: "two", startTime: 2, endTime: 3, confidence: 0.95)]
        session.resolvePendingSegment(id: pending.id, parts: parts)
        session.resolvePendingSegment(id: pending.id, parts: parts)
        XCTAssertEqual(saved.map(\.id), parts.map(\.id))
        XCTAssertFalse(session.liveTranscript.contains { $0.id == pending.id })
        XCTAssertEqual(session.liveTranscript.map(\.startTime), [0, 1, 2])
        XCTAssertEqual(session.liveTranscript.map(\.text), ["one", "mic", "two"])
        XCTAssertTrue(parts.allSatisfy { !$0.isPending })
    }

    func testMissingRowDoesNotPersist() {
        var count = 0
        let session = MeetingSession(meetingId: UUID()) { _, _ in count += 1 }
        session.resolvePendingSegment(id: UUID(), parts: [MeetingSegment(speaker: .other, text: "x", startTime: 0, endTime: 1, confidence: 1)])
        XCTAssertEqual(count, 0)
    }
}

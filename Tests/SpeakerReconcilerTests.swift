import XCTest
@testable import WhisperClip

final class SpeakerReconcilerTests: XCTestCase {
    struct Timeline: ReconcilerTimelineView {
        var coveredThrough: TimeInterval = 20
        var spans: [SpeakerTurn]
        func turns(from: TimeInterval, to: TimeInterval) -> [SpeakerTurn] {
            spans.filter { $0.endSeconds > from && $0.startSeconds < to }
        }
    }
    private func row(words: [ReconcilerWord]? = nil) -> ReconcilerRow {
        ReconcilerRow(id: UUID(), start: 0, end: 2, text: "one two", words: words)
    }
    func testSingleAndMinorityAndMajority() {
        let input = row()
        for spans in [[SpeakerTurn(slot: 0, startSeconds: 0, endSeconds: 2)],
                      [SpeakerTurn(slot: 0, startSeconds: 0, endSeconds: 1.6), SpeakerTurn(slot: 1, startSeconds: 1.6, endSeconds: 2)],
                      [SpeakerTurn(slot: 0, startSeconds: 0, endSeconds: 1.2), SpeakerTurn(slot: 1, startSeconds: 1.2, endSeconds: 2)]] {
            XCTAssertEqual(SpeakerReconciler.resolve(row: input, timeline: Timeline(spans: spans)),
                           .label(id: input.id, speaker: Speaker(displayName: "Speaker 1")))
        }
    }
    func testSplitPreservesWordsAndContiguousTimes() {
        let input = row(words: [.init(text: "one", start: 0.1, end: 0.8), .init(text: "two", start: 1.2, end: 1.9)])
        let timeline = Timeline(spans: [.init(slot: 0, startSeconds: 0, endSeconds: 1), .init(slot: 1, startSeconds: 1, endSeconds: 2)])
        guard case .split(_, let parts) = SpeakerReconciler.resolve(row: input, timeline: timeline) else { return XCTFail("Expected split") }
        XCTAssertEqual(parts.map(\.text).joined(separator: " "), "one two")
        XCTAssertEqual(parts.first?.start, 0)
        XCTAssertEqual(parts.last?.end, 2)
        XCTAssertEqual(parts[0].end, parts[1].start)
    }
    func testBoundaryWordUsesLargestOverlap() {
        let input = row(words: [.init(text: "one", start: 0.8, end: 1.5)])
        let timeline = Timeline(spans: [.init(slot: 0, startSeconds: 0, endSeconds: 1), .init(slot: 1, startSeconds: 1, endSeconds: 2)])
        XCTAssertEqual(SpeakerReconciler.resolve(row: input, timeline: timeline), .label(id: input.id, speaker: Speaker(displayName: "Speaker 2")))
    }
    func testSilenceNearAndFar() {
        let input = row()
        XCTAssertEqual(SpeakerReconciler.resolve(row: input, timeline: Timeline(spans: [.init(slot: 1, startSeconds: 2.5, endSeconds: 4)])), .label(id: input.id, speaker: Speaker(displayName: "Speaker 2")))
        XCTAssertEqual(SpeakerReconciler.resolve(row: input, timeline: Timeline(spans: [.init(slot: 1, startSeconds: 4, endSeconds: 5)])), .label(id: input.id, speaker: .other))
    }
    func testCoverageDeadlineFlushAndOrder() async {
        let input = row()
        let reconciler = SpeakerReconciler(deadlineSeconds: 10, clock: { 3 })
        await reconciler.submit(input)
        let early = await reconciler.poll(timeline: Timeline(coveredThrough: 2.19, spans: []))
        XCTAssertTrue(early.isEmpty)
        let ready = await reconciler.poll(timeline: Timeline(coveredThrough: 2.2, spans: []))
        XCTAssertEqual(ready.count, 1)
        let expired = SpeakerReconciler(deadlineSeconds: 10, clock: { 12 })
        await expired.submit(input)
        let timedOut = await expired.poll(timeline: Timeline(coveredThrough: 0, spans: []))
        XCTAssertEqual(timedOut, [.label(id: input.id, speaker: .other)])
        let later = ReconcilerRow(id: UUID(), start: 4, end: 5, text: "later", words: nil)
        await reconciler.submit(later)
        await reconciler.submit(input)
        let flushed = await reconciler.flush(timeline: Timeline(coveredThrough: 0, spans: []))
        XCTAssertEqual(flushed, [.label(id: input.id, speaker: .other), .label(id: later.id, speaker: .other)])
        let again = await reconciler.flush(timeline: Timeline(spans: []))
        XCTAssertTrue(again.isEmpty)
        XCTAssertEqual(SpeakerReconciler.deadlineSeconds(presetLatency: 11), 24)
    }
}

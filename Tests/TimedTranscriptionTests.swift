import XCTest
import FluidAudio
@testable import WhisperClip

final class TimedTranscriptionTests: XCTestCase {
    func testWordMapping() {
        func token(_ text: String, _ start: Double, _ end: Double) -> TokenTiming {
            TokenTiming(token: text, tokenId: 1, startTime: start, endTime: end, confidence: 1)
        }
        XCTAssertEqual(ParakeetVoiceToTextModel.mapWordTimings([
            token("▁hel", 0, 0.2), token("lo", 0.2, 0.4), token("<blank>", 0.4, 0.5),
            token("▁world", 0.5, 1)
        ]), [TimedWord(text: "hello", start: 0, end: 0.4), TimedWord(text: "world", start: 0.5, end: 1)])
        XCTAssertNil(ParakeetVoiceToTextModel.mapWordTimings(nil))
        XCTAssertNil(ParakeetVoiceToTextModel.mapWordTimings([]))
        XCTAssertNil(ParakeetVoiceToTextModel.mapWordTimings([token("<blank>", 0, 1)]))
    }
    func testDefaultBackendReturnsNoWordTimingsAndKeepsEvents() async throws {
        let events = LockIsolated<[StreamingTranscriptionEvent]>([])
        let text = LockIsolated("")
        let result = try await UntimedSTT().processStreamWithTimings(filepath: "unused", onEvent: { event in
            events.withValue { $0.append(event) }
        }, onToken: { value in text.withValue { $0 = value } })
        XCTAssertEqual(result, TimedTranscription(text: "hello", words: nil))
        XCTAssertEqual(text.value, "hello")
        XCTAssertEqual(events.value, [.decodingStarted, .firstToken, .finished])
    }

}

private struct UntimedSTT: VoiceToTextProtocol {
    func process(filepath: String) async throws -> String { "hello" }
}

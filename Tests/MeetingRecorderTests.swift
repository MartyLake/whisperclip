import XCTest
import AVFoundation
@testable import WhisperClip

@MainActor
final class MeetingRecorderTests: XCTestCase {
    func testMicrophoneSourceSetsActiveSpeakerLabelToMe() {
        // Contract: microphone audio always identifies as "Me" for waveform color.
        // The onAudioChunk callback sets activeSpeakerLabel = Speaker.me.displayName
        // when source == .microphone, so the waveform shows #4A9EFF (vivid blue).
        //
        // This test validates the Speaker model contract that underpins the fix:
        // 1. Speaker.me.displayName produces "Me"
        // 2. Speaker(displayName: "Me") round-trips back to .me
        // 3. .me has colorIndex 0 (palette slot for vivid blue)

        let expectedLabel = Speaker.me.displayName
        XCTAssertEqual(expectedLabel, "Me", "Speaker.me.displayName must be 'Me'")

        // Round-trip: the label stored in activeSpeakerLabel -> Speaker(displayName:) -> palette lookup
        let resolvedSpeaker = Speaker(displayName: expectedLabel)
        XCTAssertEqual(resolvedSpeaker, .me, "Speaker(displayName: 'Me') must resolve to .me")
        XCTAssertEqual(resolvedSpeaker.colorIndex, 0, ".me must have colorIndex 0 for palette slot #4A9EFF")

        // Verify AudioSource.microphone maps to Speaker.me via source.speaker
        let micSpeaker = AudioSource.microphone.speaker
        XCTAssertEqual(micSpeaker, .me, "AudioSource.microphone.speaker must be .me")
        XCTAssertEqual(micSpeaker.displayName, "Me", "Mic speaker displayName must be 'Me'")
    }

    func testTranscriptionQueueProcessesSystemSourceChunks() async throws {
        let queue = TranscriptionQueue()
        var processedSources: [AudioSource] = []

        let systemSamples = Array(repeating: Float(0.1), count: 80_000)

        await queue.enqueue(
            source: .system,
            samples: systemSamples,
            startTime: 0.0
        ) { source, _, _ in
            processedSources.append(source)
        }

        await queue.drain()

        XCTAssertEqual(processedSources.count, 1, "Queue should process one system source chunk")
        XCTAssertEqual(processedSources[0], .system, "Processed source should be .system")
    }
}

final class LockIsolated<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&storage)
    }
}

private final class TimedMeetingSTT: VoiceToTextProtocol {
    let words: [TimedWord]?
    var inputSampleCounts: [Int] = []
    init(words: [TimedWord]?) { self.words = words }
    func process(filepath: String) async throws -> String { "one two" }
    func processStreamWithTimings(
        filepath: String,
        onEvent: @escaping @MainActor @Sendable (StreamingTranscriptionEvent) -> Void,
        onToken: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> TimedTranscription {
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: filepath))
        inputSampleCounts.append(Int(file.length))
        await onToken("one two")
        return TimedTranscription(text: "one two", words: words)
    }
}

extension MeetingRecorderTests {
    func testStopDrainsASRThenTimelineAndPersistsSplitExactlyOnce() async {
        var saved: [MeetingSegment] = []
        let session = MeetingSession(meetingId: UUID()) { segment, _ in saved.append(segment) }
        let probabilities = (0..<200).flatMap { frame -> [Float] in frame < 100 ? [0.9, 0] : [0, 0.9] }
        let provider = MockStreamingDiarizationProvider(finishResults: [
            StreamingDiarizationChunk(probabilities: probabilities, frameCount: 200, numSpeakers: 2)
        ])
        let recorder = MeetingRecorder(
            voiceToText: TimedMeetingSTT(words: [.init(text: "one", start: 0.1, end: 0.8),
                                                .init(text: "two", start: 1.2, end: 1.9)]),
            session: session, speakerBufferManager: SpeakerBufferManager(provider: provider))
        await recorder.consumeSystemAudio([Float](repeating: 0.5, count: 32_000), at: 5)
        _ = await recorder.stopRecording()
        XCTAssertEqual(saved.map(\.text), ["one", "two"])
        XCTAssertEqual(saved.map(\.speaker), [.labeled("Speaker 1"), .labeled("Speaker 2")])
        XCTAssertEqual(session.liveTranscript.map(\.id), saved.map(\.id))
        XCTAssertTrue(session.liveTranscript.allSatisfy { !$0.isPending })
        XCTAssertEqual(saved.first?.startTime, 5)
        XCTAssertEqual(saved.last?.endTime, 7)
    }

    func testStopWithoutWordTimingsUsesMajorityAndDoesNotSplit() async {
        var saved: [MeetingSegment] = []
        let session = MeetingSession(meetingId: UUID()) { segment, _ in saved.append(segment) }
        let probabilities = (0..<200).flatMap { frame -> [Float] in frame < 120 ? [0.9, 0] : [0, 0.9] }
        let manager = SpeakerBufferManager(provider: MockStreamingDiarizationProvider(finishResults: [
            StreamingDiarizationChunk(probabilities: probabilities, frameCount: 200, numSpeakers: 2)
        ]))
        let recorder = MeetingRecorder(voiceToText: TimedMeetingSTT(words: nil), session: session, speakerBufferManager: manager)
        await recorder.consumeSystemAudio([Float](repeating: 0.5, count: 32_000), at: 0)
        _ = await recorder.stopRecording()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.text, "one two")
        XCTAssertEqual(saved.first?.speaker, .labeled("Speaker 1"))
    }

    func testStopWithoutDiarizerKeepsShortFinalPhraseAsOther() async {
        var saved: [MeetingSegment] = []
        let session = MeetingSession(meetingId: UUID()) { segment, _ in saved.append(segment) }
        let stt = TimedMeetingSTT(words: nil)
        let recorder = MeetingRecorder(voiceToText: stt, session: session)
        await recorder.consumeSystemAudio([Float](repeating: 0.5, count: 8_000), at: 3)
        _ = await recorder.stopRecording()
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.speaker, .other)
        XCTAssertEqual(saved.first?.endTime, 3.5)
        XCTAssertEqual(stt.inputSampleCounts, [16_000])
        XCTAssertTrue(session.liveTranscript.allSatisfy { !$0.isPending })
    }
    func testTinyTailNeverCallsASROrPersistsFailureRow() async {
        var saved: [MeetingSegment] = []
        let session = MeetingSession(meetingId: UUID()) { segment, _ in saved.append(segment) }
        let stt = TimedMeetingSTT(words: nil)
        let recorder = MeetingRecorder(voiceToText: stt, session: session)
        await recorder.consumeSystemAudio([Float](repeating: 0.5, count: 3_200), at: 0)
        _ = await recorder.stopRecording()
        XCTAssertTrue(stt.inputSampleCounts.isEmpty)
        XCTAssertTrue(saved.isEmpty)
        XCTAssertTrue(session.liveTranscript.isEmpty)
    }

    func testJitterDoesNotPadDiarizerOrFragmentASR() async {
        var saved: [MeetingSegment] = []
        let session = MeetingSession(meetingId: UUID()) { segment, _ in saved.append(segment) }
        let provider = MockStreamingDiarizationProvider()
        let stt = TimedMeetingSTT(words: nil)
        let recorder = MeetingRecorder(voiceToText: stt, session: session,
                                      speakerBufferManager: SpeakerBufferManager(provider: provider))
        for index in 0..<100 {
            let jitter = index % 2 == 0 ? 0.0 : 0.004
            await recorder.consumeSystemAudio([Float](repeating: 0.5, count: 320),
                                              at: Double(index) * 0.02 + jitter)
        }
        _ = await recorder.stopRecording()
        XCTAssertEqual(provider.appendedSampleCount(), 32_000)
        XCTAssertEqual(stt.inputSampleCounts, [32_000])
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.endTime ?? -1, 2, accuracy: 0.0001)
    }

}

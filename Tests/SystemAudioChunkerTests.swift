import XCTest
@testable import WhisperClip

final class SystemAudioChunkerTests: XCTestCase {
    private let rate = 16_000
    func testPauseCutAndLeadingSilenceClock() {
        var chunker = SystemAudioChunker(thresholdDB: -45)
        let chunks = chunker.append([Float](repeating: 0, count: rate) + [Float](repeating: 0.5, count: rate * 2) + [Float](repeating: 0, count: rate / 2), at: 10)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first!.startTime, 11, accuracy: 0.0001)
        XCTAssertEqual(chunks.first?.samples.count, rate * 2)
        XCTAssertNil(chunker.flush())
    }
    func testMinimumAndFlush() {
        var chunker = SystemAudioChunker(thresholdDB: -45)
        XCTAssertTrue(chunker.append([Float](repeating: 0.5, count: rate / 2) + [Float](repeating: 0, count: rate * 2 / 5), at: 0).isEmpty)
        let chunks = chunker.append([Float](repeating: 0, count: rate / 10), at: 0.9)
        XCTAssertEqual(chunks.first?.samples.count, rate)
        XCTAssertEqual(chunks.first?.samples.filter { $0 > 0 }.count, rate / 2)
        XCTAssertTrue(chunker.append([Float](repeating: 0.5, count: 123), at: 2).isEmpty)
        XCTAssertNotNil(chunker.flush())
        XCTAssertNil(chunker.flush())
    }
    func testCapAndSpeechPreservationAcrossBatches() {
        var chunker = SystemAudioChunker(thresholdDB: -45)
        var chunks: [SystemAudioChunk] = []
        let input = (0..<(rate * 20 + 123)).map { Float($0 % 100 + 1) / 100 }
        var index = 0
        while index < input.count {
            let end = min(index + 777, input.count)
            chunks += chunker.append(Array(input[index..<end]), at: Double(index) / Double(rate))
            index = end
        }
        if let tail = chunker.flush() { chunks.append(tail) }
        XCTAssertEqual(chunks.flatMap(\.samples), input)
        XCTAssertTrue(chunks.allSatisfy { $0.samples.count <= rate * 8 })
        for pair in zip(chunks, chunks.dropFirst()) {
            XCTAssertEqual(pair.0.startTime + Double(pair.0.samples.count) / Double(rate), pair.1.startTime, accuracy: 0.0001)
        }
    }
    func testGapAndSilence() {
        var chunker = SystemAudioChunker(thresholdDB: -45)
        XCTAssertTrue(chunker.append([Float](repeating: 0, count: rate), at: 0).isEmpty)
        XCTAssertNil(chunker.flush())
        XCTAssertTrue(chunker.append([Float](repeating: 0.5, count: rate), at: 2).isEmpty)
        let chunks = chunker.append([Float](repeating: 0.5, count: rate), at: 4)
        XCTAssertEqual(chunks.first?.startTime, 2)
        XCTAssertEqual(chunker.flush()?.startTime, 4)
    }
    func testCapChoosesQuietestFrameInFinalSecond() {
        var chunker = SystemAudioChunker(thresholdDB: -45)
        var audio = [Float](repeating: 0.5, count: rate * 8)
        let quietStart = rate * 38 / 5
        audio.replaceSubrange(quietStart..<(quietStart + rate / 50), with: repeatElement(Float(0.01), count: rate / 50))
        let chunks = chunker.append(audio, at: 0)
        XCTAssertEqual(chunks.first?.samples.count, quietStart)
        XCTAssertEqual((chunks.first?.samples ?? []) + (chunker.flush()?.samples ?? []), audio)
    }

    func testGapRetainsPartialFrameOfSpeech() {
        var chunker = SystemAudioChunker(thresholdDB: -45)
        let short = [Float](repeating: 0.5, count: 123)
        XCTAssertTrue(chunker.append(short, at: 0).isEmpty)
        let chunks = chunker.append(short, at: 1)
        XCTAssertEqual(chunks.first?.samples, short)
        XCTAssertEqual(chunker.flush()?.samples, short)
    }

    func testCallbackJitterKeepsPhrasesAndSampleTimes() {
        var chunker = SystemAudioChunker(thresholdDB: -45)
        let batchSize = 320
        var chunks: [SystemAudioChunk] = []
        // Two seconds of speech, half a second of silence, then two seconds of speech.
        let input = [Float](repeating: 0.5, count: rate * 2)
            + [Float](repeating: 0, count: rate / 2)
            + [Float](repeating: 0.25, count: rate * 2)
        let jitter: [Double] = [0, 0.004, -0.003, 0.002, -0.005]
        for index in stride(from: 0, to: input.count, by: batchSize) {
            let end = min(index + batchSize, input.count)
            chunks += chunker.append(Array(input[index..<end]),
                                     at: 10 + Double(index) / Double(rate) + jitter[(index / batchSize) % jitter.count])
        }
        if let tail = chunker.flush() { chunks.append(tail) }
        XCTAssertEqual(chunks.count, 2)
        XCTAssertEqual(chunks[0].samples.count, rate * 2)
        XCTAssertEqual(chunks[1].samples.count, rate * 2)
        XCTAssertEqual(chunks[0].startTime, 10, accuracy: 0.0001)
        XCTAssertEqual(chunks[1].startTime, 12.5, accuracy: 0.0001)
        XCTAssertEqual(chunks.flatMap(\.samples).filter { $0 != 0 }, input.filter { $0 != 0 })
    }

    func testRealGapReanchorsAfterJitter() {
        var chunker = SystemAudioChunker(thresholdDB: -45)
        let batch = [Float](repeating: 0.5, count: rate / 2)
        XCTAssertTrue(chunker.append(batch, at: 5).isEmpty)
        XCTAssertTrue(chunker.append(batch, at: 5.503).isEmpty)
        let chunks = chunker.append(batch, at: 6.5)
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first?.samples.count, rate)
        XCTAssertEqual(chunker.flush()?.startTime, 6.5)
    }

}

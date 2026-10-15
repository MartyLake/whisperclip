import Foundation

struct SystemAudioChunk: Sendable {
    let samples: [Float]
    let startTime: TimeInterval
}

/// Keeps callback jitter out of the audio clock. Only a substantial forward gap
/// reanchors the stream; otherwise time advances by the number of captured samples.
struct SystemAudioSampleClock {
    private(set) var nextTime: TimeInterval?
    static let gapTolerance: TimeInterval = 0.4

    mutating func advance(sampleCount: Int, sampleRate: Int, at captureTime: TimeInterval) -> (time: TimeInterval, isGap: Bool) {
        let isGap = nextTime.map { captureTime > $0 + Self.gapTolerance } ?? false
        let time = isGap ? captureTime : (nextTime ?? captureTime)
        nextTime = time + Double(sampleCount) / Double(sampleRate)
        return (time, isGap)
    }
}

/// Frame-based pause cutter. Only leading/trailing silence is discarded.
struct SystemAudioChunker {
    private let sampleRate: Int
    private let frameSize: Int
    private let thresholdDB: Float
    private var samples: [Float] = []
    private var startTime: TimeInterval = 0
    private var clock = SystemAudioSampleClock()
    private var scanned = 0
    private var silenceStart: Int?
    private var hasSpeech = false

    init(thresholdDB: Float, sampleRate: Int = 16_000) {
        self.thresholdDB = thresholdDB
        self.sampleRate = sampleRate
        frameSize = max(1, sampleRate / 50)
    }

    mutating func append(_ input: [Float], at captureTime: TimeInterval) -> [SystemAudioChunk] {
        guard !input.isEmpty else { return [] }
        var output: [SystemAudioChunk] = []
        var nextClock = clock
        let position = nextClock.advance(sampleCount: input.count, sampleRate: sampleRate, at: captureTime)
        if position.isGap, let tail = flush() { output.append(tail) }
        clock = nextClock
        if samples.isEmpty { startTime = position.time }
        samples.append(contentsOf: input)
        while scanned + frameSize <= samples.count {
            let quiet = power(samples[scanned..<(scanned + frameSize)]) < thresholdDB
            if !hasSpeech && quiet {
                discard(frameSize)
                continue
            }
            if quiet {
                if silenceStart == nil { silenceStart = scanned }
            } else {
                hasSpeech = true
                silenceStart = nil
            }
            scanned += frameSize
            if let silenceStart, scanned >= sampleRate,
               scanned - silenceStart >= sampleRate * 2 / 5 {
                // Short utterances retain enough trailing silence to meet ASR's 1 s chunk floor.
                let cut = max(silenceStart, sampleRate)
                output.append(SystemAudioChunk(samples: Array(samples[..<cut]), startTime: startTime))
                discard(scanned)
            } else if scanned >= sampleRate * 8 {
                let lower = sampleRate * 7
                let upper = sampleRate * 8
                var cut = lower
                var quietest = Float.infinity
                for index in stride(from: lower, to: upper, by: frameSize) {
                    let level = power(samples[index..<min(index + frameSize, upper)])
                    if level < quietest { quietest = level; cut = index }
                }
                output.append(SystemAudioChunk(samples: Array(samples[..<cut]), startTime: startTime))
                discard(cut)
            }
        }
        return output
    }

    mutating func flush() -> SystemAudioChunk? {
        defer {
            samples = []
            scanned = 0
            silenceStart = nil
            hasSpeech = false
            clock = SystemAudioSampleClock()
        }
        // A partial final frame may contain speech even if no complete frame did.
        guard !samples.isEmpty,
              hasSpeech || power(samples[...]) >= thresholdDB else { return nil }
        return SystemAudioChunk(samples: samples, startTime: startTime)
    }

    private mutating func discard(_ count: Int) {
        samples.removeFirst(count)
        startTime += Double(count) / Double(sampleRate)
        scanned = 0
        silenceStart = nil
        hasSpeech = false
    }

    private func power(_ frame: ArraySlice<Float>) -> Float {
        let energy = frame.reduce(Float.zero) { $0 + $1 * $1 } / Float(max(1, frame.count))
        return 10 * log10(max(energy, 1e-14))
    }
}

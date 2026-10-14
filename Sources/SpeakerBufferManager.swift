import Foundation

/// Converts streaming slot probabilities into bounded, timeline-aligned audio buffers.
actor SpeakerBufferManager {
    nonisolated let buffers: AsyncStream<ClosedSpeakerBuffer>
    nonisolated let pollingInterval: UInt64
    nonisolated let sampleRate: Int
    nonisolated let maxSamplesPerBuffer: Int
    nonisolated let minSamplesPerBuffer: Int
    nonisolated(unsafe) var onSpeechDetected: (@Sendable (TimeInterval, String) -> Void)?

    private let provider: any StreamingDiarizationProvider
    private var continuation: AsyncStream<ClosedSpeakerBuffer>.Continuation?
    private var pollingTask: Task<Void, Never>?
    private var timeline = SpeakerTimeline()
    private var audio: [Float] = []
    private var sessionStartTime: TimeInterval?
    /// Timeline offset, in seconds, represented by `audio[0]`.
    private var audioBaseSeconds: Double = 0
    private var lastInputEndTime: TimeInterval?
    private var emittedThrough: Double = 0
    private var observedFrameCount = 0
    private var activeObservedSlot: UInt8 = 0
    private var silenceFrames = 0

    init(provider: any StreamingDiarizationProvider, sampleRate: Int = 16_000,
         pollingInterval: UInt64 = 150_000_000) {
        self.provider = provider
        self.sampleRate = sampleRate
        self.pollingInterval = pollingInterval
        maxSamplesPerBuffer = sampleRate * 30
        minSamplesPerBuffer = sampleRate / 2
        var streamContinuation: AsyncStream<ClosedSpeakerBuffer>.Continuation?
        buffers = AsyncStream { streamContinuation = $0 }
        continuation = streamContinuation
    }

    func timelineSnapshot() -> SpeakerTimeline { timeline }

    func onAudioBatch(_ samples: [Float], atTime time: TimeInterval) {
        guard !samples.isEmpty else { return }
        if sessionStartTime == nil {
            sessionStartTime = time
            audioBaseSeconds = 0
        }
        if let expected = lastInputEndTime, time > expected {
            let missing = Int(((time - expected) * Double(sampleRate)).rounded())
            if missing > 0 {
                let silence = [Float](repeating: 0, count: missing)
                audio.append(contentsOf: silence)
                do { try provider.append(silence) }
                catch { logProviderError(error) }
            }
        }
        audio.append(contentsOf: samples)
        do { try provider.append(samples) }
        catch { logProviderError(error) }
        lastInputEndTime = time + Double(samples.count) / Double(sampleRate)
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task {
            while !Task.isCancelled {
                processAvailable(final: false)
                do { try await Task.sleep(nanoseconds: pollingInterval) }
                catch { break }
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        do { appendResults(try provider.finish()) }
        catch { logProviderError(error) }
        emitTurns(final: true)
        continuation?.finish()
        continuation = nil
        audio.removeAll(keepingCapacity: false)
    }

    private func processAvailable(final: Bool) {
        do { appendResults(try provider.process()) }
        catch { logProviderError(error); return }
        emitTurns(final: final)
    }

    private func appendResults(_ chunks: [StreamingDiarizationChunk]) {
        for chunk in chunks {
            timeline.append(probabilities: chunk.probabilities, frameCount: chunk.frameCount,
                            numSpeakers: chunk.numSpeakers)
        }
        let sessionStart = sessionStartTime ?? 0
        while observedFrameCount < timeline.frames.count {
            let slot = timeline.frames[observedFrameCount]
            if slot == 0 {
                silenceFrames += 1
                if silenceFrames >= 20 { activeObservedSlot = 0 }
            } else {
                silenceFrames = 0
                if slot != activeObservedSlot {
                    onSpeechDetected?(sessionStart + Double(observedFrameCount) * SpeakerTimeline.frameSeconds,
                                      timeline.label(forSlot: Int(slot) - 1))
                    activeObservedSlot = slot
                }
            }
            observedFrameCount += 1
        }
    }

    private func emitTurns(final: Bool) {
        guard let sessionStartTime else { return }
        let covered = timeline.coveredSeconds
        let safeEnd = final ? covered : max(0, covered - SpeakerTimeline.mergeGapSeconds)
        guard safeEnd > emittedThrough else { return }
        let allTurns = timeline.turns(from: emittedThrough, to: covered)
        let openTurn = final ? nil : allTurns.first(where: { $0.endSeconds >= safeEnd })
        let capBoundary = openTurn.map { $0.startSeconds + 30 }
        var turns = allTurns.filter { final || $0.endSeconds < safeEnd }
        if let openTurn, let capBoundary, capBoundary <= safeEnd {
            turns.append(SpeakerTurn(slot: openTurn.slot, startSeconds: openTurn.startSeconds,
                                     endSeconds: min(openTurn.endSeconds, capBoundary)))
        }
        var cursor = emittedThrough
        for turn in turns {
            if turn.startSeconds > cursor { cursor = turn.startSeconds }
            var start = max(turn.startSeconds, cursor)
            while start < turn.endSeconds {
                let end = min(turn.endSeconds, start + 30)
                let lower = Int((start * Double(sampleRate)).rounded())
                let upper = Int((end * Double(sampleRate)).rounded())
                let baseSample = Int((audioBaseSeconds * Double(sampleRate)).rounded())
                let audioLower = max(0, lower - baseSample)
                let audioUpper = min(audio.count, upper - baseSample)
                if audioUpper > audioLower, audioUpper - audioLower >= minSamplesPerBuffer {
                    let label = turn.label
                    continuation?.yield(ClosedSpeakerBuffer(samples: Array(audio[audioLower..<audioUpper]),
                                                              speakerLabel: label,
                                                              startTime: sessionStartTime + start))
                }
                cursor = end
                start = end
            }
        }
        let pendingStart = openTurn.map { turn in
            (turn.startSeconds + 30 <= safeEnd) ? turn.startSeconds + 30 : turn.startSeconds
        }
        emittedThrough = min(safeEnd, pendingStart ?? safeEnd)
        // Retain at most the unresolved tail plus one 30 s cap window.
        let keepFrom = max(0, emittedThrough - 30)
        let baseSample = Int((audioBaseSeconds * Double(sampleRate)).rounded())
        let keepSample = Int((keepFrom * Double(sampleRate)).rounded())
        let discardSamples = min(audio.count, max(0, keepSample - baseSample))
        if discardSamples > 0 {
            audio.removeFirst(discardSamples)
            audioBaseSeconds += Double(discardSamples) / Double(sampleRate)
        }
    }

    private func logProviderError(_ error: Error) {
        Logger.log("Speaker diarization provider error: \(error.localizedDescription)",
                   log: Logger.general, type: .error)
    }
}

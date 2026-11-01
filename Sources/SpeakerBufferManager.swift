import Foundation

/// Feeds the streaming diarizer and owns its compact speaker timeline.
actor SpeakerBufferManager {
    nonisolated let pollingInterval: UInt64
    nonisolated let sampleRate: Int
    nonisolated(unsafe) var onSpeechDetected: (@Sendable (TimeInterval, String) -> Void)?

    private let provider: any StreamingDiarizationProvider
    private var pollingTask: Task<Void, Never>?
    private var timeline = SpeakerTimeline()
    private(set) var sessionStartTime: TimeInterval?
    private var lastInputEndTime: TimeInterval?
    private var observedFrameCount = 0
    private var activeObservedSlot: UInt8 = 0
    private var silenceFrames = 0

    init(provider: any StreamingDiarizationProvider, sampleRate: Int = 16_000,
         pollingInterval: UInt64 = 150_000_000) {
        self.provider = provider
        self.sampleRate = sampleRate
        self.pollingInterval = pollingInterval

    }

    func timelineSnapshot() -> SpeakerTimeline { timeline }

    func timelineView(from captureTime: TimeInterval = 0) -> SpeakerTimelineWindow {
        let offset = sessionStartTime ?? 0
        // Include a second before the row for silence fallback and turn merging.
        let lower = min(timeline.frames.count, max(0, Int(((captureTime - offset - 1.2) / SpeakerTimeline.frameSeconds).rounded(.down))))
        return SpeakerTimelineWindow(frames: Array(timeline.frames[lower...]),
                                     startTime: offset + Double(lower) * SpeakerTimeline.frameSeconds,
                                     coveredThrough: offset + timeline.coveredSeconds)
    }

    func onAudioBatch(_ samples: [Float], atTime time: TimeInterval) {
        guard !samples.isEmpty else { return }
        if sessionStartTime == nil {
            sessionStartTime = time
        }
        if let expected = lastInputEndTime, time > expected {
            let missing = Int(((time - expected) * Double(sampleRate)).rounded())
            if missing > 0 {
                let silence = [Float](repeating: 0, count: missing)
                do { try provider.append(silence) }
                catch { logProviderError(error) }
            }
        }
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
    }

    private func processAvailable(final: Bool) {
        do { appendResults(try provider.process()) }
        catch { logProviderError(error); return }
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

    private func logProviderError(_ error: Error) {
        Logger.log("Speaker diarization provider error" + (GenericHelper.logSensitiveData() ? ": \(error)" : ""),
                   log: Logger.general, type: .error)
    }
}

struct SpeakerTimelineWindow: ReconcilerTimelineView {
    let frames: [UInt8]
    let startTime: TimeInterval
    let coveredThrough: TimeInterval

    func turns(from: TimeInterval, to: TimeInterval) -> [SpeakerTurn] {
        var timeline = SpeakerTimeline()
        timeline.appendFrames(frames)
        return timeline.turns(from: max(0, from - startTime), to: max(0, to - startTime)).map {
            SpeakerTurn(slot: $0.slot, startSeconds: $0.startSeconds + startTime,
                        endSeconds: $0.endSeconds + startTime)
        }
    }
}

import Foundation

/// Compact 10 ms speaker timeline. One UInt8 per frame stores the winning slot + 1
/// (zero means silence), so an hour uses about 360 KB instead of 11.5 MB of probabilities.
struct SpeakerTimeline: Sendable {
    static let activityThreshold: Float = 0.5
    static let mergeGapSeconds: Double = 0.2
    static let minimumTurnSeconds: Double = 0.2
    static let frameSeconds: Double = 0.01

    private(set) var frames: [UInt8] = []
    var coveredSeconds: Double { Double(frames.count) * Self.frameSeconds }

    mutating func append(probabilities: [Float], frameCount: Int, numSpeakers: Int) {
        guard frameCount > 0, numSpeakers > 0 else { return }
        for frame in 0..<frameCount {
            let start = frame * numSpeakers
            guard start < probabilities.count else { frames.append(0); continue }
            var winner = -1
            var highest = Self.activityThreshold
            for slot in 0..<min(numSpeakers, probabilities.count - start) {
                let value = probabilities[start + slot]
                if value > highest { highest = value; winner = slot }
            }
            frames.append(winner >= 0 && winner < 255 ? UInt8(winner + 1) : 0)
        }
    }

    func label(forSlot slot: Int) -> String { "Speaker \(slot + 1)" }

    func dominantSpeaker(from start: Double, to end: Double) -> Int? {
        let lower = max(0, Int((start / Self.frameSeconds).rounded(.down)))
        let upper = min(frames.count, Int((end / Self.frameSeconds).rounded(.up)))
        guard lower < upper else { return nil }
        var counts: [UInt8: Int] = [:]
        for frame in frames[lower..<upper] where frame > 0 { counts[frame, default: 0] += 1 }
        guard let winner = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        return Int(winner) - 1
    }

    func turns(from start: Double, to end: Double) -> [SpeakerTurn] {
        let lower = max(0, Int((start / Self.frameSeconds).rounded(.down)))
        let upper = min(frames.count, Int((end / Self.frameSeconds).rounded(.up)))
        guard lower < upper else { return [] }
        var spans: [(slot: UInt8, start: Int, end: Int)] = []
        var runStart = lower
        var runSlot = frames[lower]
        for index in (lower + 1)..<upper {
            let slot = frames[index]
            if slot != runSlot {
                spans.append((runSlot, runStart, index))
                runStart = index
                runSlot = slot
            }
        }
        spans.append((runSlot, runStart, upper))
        spans = spans.filter { $0.slot > 0 }
        let gap = Int((Self.mergeGapSeconds / Self.frameSeconds).rounded())
        var merged: [(slot: UInt8, start: Int, end: Int)] = []
        for span in spans {
            if let last = merged.indices.last, merged[last].slot == span.slot,
               span.start - merged[last].end <= gap {
                merged[last].end = span.end
            } else { merged.append(span) }
        }
        let minimum = Int((Self.minimumTurnSeconds / Self.frameSeconds).rounded(.up))
        return merged.filter { $0.end - $0.start >= minimum }.map {
            SpeakerTurn(slot: Int($0.slot) - 1, startSeconds: Double($0.start) * Self.frameSeconds,
                        endSeconds: Double($0.end) * Self.frameSeconds)
        }
    }
}

struct SpeakerTurn: Sendable, Equatable {
    let slot: Int
    let startSeconds: Double
    let endSeconds: Double
    var label: String { "Speaker \(slot + 1)" }
}

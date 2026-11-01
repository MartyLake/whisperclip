import Foundation

protocol ReconcilerTimelineView: Sendable {
    var coveredThrough: TimeInterval { get }
    func turns(from: TimeInterval, to: TimeInterval) -> [SpeakerTurn]
}

struct ReconcilerWord: Sendable, Equatable {
    let text: String
    let start: TimeInterval
    let end: TimeInterval
}

struct ReconcilerRow: Sendable {
    let id: UUID
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    let words: [ReconcilerWord]?
}

struct ReconcilerPart: Sendable, Equatable {
    let speaker: Speaker
    var text: String
    let start: TimeInterval
    var end: TimeInterval
}

enum ReconcilerResolution: Sendable, Equatable {
    case label(id: UUID, speaker: Speaker)
    case split(id: UUID, parts: [ReconcilerPart])
}

/// Joins independently produced ASR rows and speaker activity using capture seconds.
actor SpeakerReconciler {
    private let deadlineSeconds: TimeInterval
    private let clock: @Sendable () -> TimeInterval
    private var rows: [ReconcilerRow] = []

    init(deadlineSeconds: TimeInterval, clock: @escaping @Sendable () -> TimeInterval) {
        self.deadlineSeconds = deadlineSeconds
        self.clock = clock
    }

    nonisolated static func deadlineSeconds(presetLatency: TimeInterval) -> TimeInterval {
        max(10, 2 * presetLatency + 2)
    }

    var oldestQueuedStart: TimeInterval? { rows.map(\.start).min() }

    func submit(_ row: ReconcilerRow) {
        guard !rows.contains(where: { $0.id == row.id }) else { return }
        rows.append(row)
        rows.sort { $0.start < $1.start }
    }

    func poll(timeline: any ReconcilerTimelineView) -> [ReconcilerResolution] {
        var output: [ReconcilerResolution] = []
        let now = clock()
        rows.removeAll { row in
            if timeline.coveredThrough >= row.end + 0.2 {
                output.append(Self.resolve(row: row, timeline: timeline))
                return true
            }
            if now >= row.end + deadlineSeconds {
                Logger.log("Speaker reconciliation deadline exceeded for row \(row.id)", log: Logger.general)
                output.append(.label(id: row.id, speaker: .other))
                return true
            }
            return false
        }
        return output
    }

    func flush(timeline: any ReconcilerTimelineView) -> [ReconcilerResolution] {
        defer { rows.removeAll() }
        return rows.map { Self.resolve(row: $0, timeline: timeline) }
    }

    nonisolated static func resolve(row: ReconcilerRow, timeline: any ReconcilerTimelineView) -> ReconcilerResolution {
        let turns = timeline.turns(from: row.start, to: row.end)
        var durations: [Int: Double] = [:]
        for turn in turns {
            durations[turn.slot, default: 0] += max(0, min(row.end, turn.endSeconds) - max(row.start, turn.startSeconds))
        }
        let eligible = durations.filter { $0.value >= 0.6 - 0.000_001 }
        func label(_ slot: Int?) -> ReconcilerResolution {
            .label(id: row.id, speaker: slot.map { Speaker(displayName: "Speaker \($0 + 1)") } ?? .other)
        }
        guard !eligible.isEmpty else {
            // Only silence gets a neighbouring turn; short activity is ignored as noise.
            guard durations.isEmpty else { return label(nil) }
            let nearby = timeline.turns(from: row.start - 1, to: row.end + 1)
            let nearest = nearby.min { distance($0, row.start, row.end) < distance($1, row.start, row.end) }
            return label(nearest.flatMap { distance($0, row.start, row.end) <= 1 ? $0.slot : nil })
        }
        let majority = eligible.keys.sorted().max { eligible[$0]! < eligible[$1]! }
        guard eligible.count > 1, let words = row.words, !words.isEmpty else { return label(majority) }
        let candidates = turns.filter { eligible[$0.slot] != nil }
        var parts: [ReconcilerPart] = []
        for word in words {
            var overlaps: [Int: Double] = [:]
            for turn in candidates {
                overlaps[turn.slot, default: 0] += max(0, min(word.end, turn.endSeconds) - max(word.start, turn.startSeconds))
            }
            let dominant = overlaps.keys.sorted().max { overlaps[$0]! < overlaps[$1]! }
            let slot: Int
            if let dominant, overlaps[dominant, default: 0] > 0 {
                slot = dominant
            } else {
                slot = candidates.min { distance($0, word.start, word.end) < distance($1, word.start, word.end) }!.slot
            }
            let speaker = Speaker(displayName: "Speaker \(slot + 1)")
            if let last = parts.indices.last, parts[last].speaker == speaker {
                parts[last].text += " " + word.text
                parts[last].end = word.end
            } else {
                // Assign the inter-word gap to the preceding part, keeping ranges contiguous.
                if let last = parts.indices.last { parts[last].end = word.start }
                parts.append(ReconcilerPart(speaker: speaker, text: word.text,
                                            start: parts.isEmpty ? row.start : word.start, end: word.end))
            }
        }
        guard parts.count > 1 else { return .label(id: row.id, speaker: parts[0].speaker) }
        parts[parts.count - 1].end = row.end
        return .split(id: row.id, parts: parts)
    }

    private nonisolated static func distance(_ turn: SpeakerTurn, _ start: Double, _ end: Double) -> Double {
        max(0, max(start - turn.endSeconds, turn.startSeconds - end))
    }
}

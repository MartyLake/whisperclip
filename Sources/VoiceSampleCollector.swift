import Foundation

/// Capture-clock audio, bounded to 30 seconds. Growing turns replace their earlier
/// sample and contribute only new speech time, rather than being counted twice.
struct VoiceSampleCollector: Sendable {
    private struct Piece: Sendable {
        let start: Double
        let preferred: Bool
        let audio: [Float]
    }
    private var ring: [Float] = []
    private var ringStart: Double = 0
    private var consumed: [Int: [Double: Double]] = [:]
    private var pieces: [Int: [Piece]] = [:]
    private var preferredStarts: [Int: Set<Double>] = [:]
    private var milestones: [Int: Int] = [:]
    private(set) var speechSeconds: [Int: Double] = [:]
    private let rate = 16_000

    mutating func appendAudio(_ samples: [Float], at time: Double) {
        if ring.isEmpty { ringStart = time }
        let expected = ringStart + Double(ring.count) / Double(rate)
        if abs(time - expected) > 0.05 { ring = []; ringStart = time }
        ring.append(contentsOf: samples)
        let excess = max(0, ring.count - 30 * rate)
        if excess > 0 { ring.removeFirst(excess); ringStart += Double(excess) / Double(rate) }
    }

    mutating func consume(_ turns: [SpeakerTurn]) {
        for turn in turns {
            let duration = max(0, turn.endSeconds - turn.startSeconds)
            let previous = consumed[turn.slot]?[turn.startSeconds] ?? 0
            guard duration > previous + 0.00001 else { continue }
            consumed[turn.slot, default: [:]][turn.startSeconds] = duration
            speechSeconds[turn.slot, default: 0] += duration - previous
            let preferred = duration >= 1.2 && duration <= 5
            if preferred { preferredStarts[turn.slot, default: []].insert(turn.startSeconds) }
            else { preferredStarts[turn.slot]?.remove(turn.startSeconds) }
            let enoughPreferred = preferredStarts[turn.slot, default: []].count >= 3
            if enoughPreferred { pieces[turn.slot]?.removeAll { !$0.preferred } }
            guard preferred || (!enoughPreferred && duration >= 0.6) else { continue }
            let trim = duration - 0.2 >= 0.6 ? 0.1 : 0
            // If the full turn has expired from the ring, retain its earlier
            // collected piece. Never manufacture a sample from incomplete audio.
            let start = turn.startSeconds + trim
            let lower = Int(((start - ringStart) * Double(rate)).rounded())
            let upper = Int(((turn.endSeconds - trim - ringStart) * Double(rate)).rounded())
            guard lower >= 0, upper <= ring.count, upper - lower >= rate * 3 / 10 else { continue }
            // Entirely expired closed turns have no retrievable audio.
            if turn.endSeconds <= ringStart { continue }
            pieces[turn.slot, default: []].removeAll { $0.start == turn.startSeconds }
            pieces[turn.slot, default: []].append(Piece(start: turn.startSeconds, preferred: preferred,
                                                      audio: Array(ring[lower..<upper])))
            let sorted = pieces[turn.slot, default: []].sorted { $0.audio.count > $1.audio.count }
            var remaining = 15 * rate
            pieces[turn.slot] = sorted.compactMap { piece in
                guard remaining > 0 else { return nil }
                let selected = Array(piece.audio.prefix(remaining))
                remaining -= selected.count
                return Piece(start: piece.start, preferred: piece.preferred, audio: selected)
            }
        }
    }

    func audio(for slot: Int) -> [Float] { pieces[slot, default: []].flatMap { $0.audio } }

    mutating func readyForEmbedding(slot: Int) -> Bool {
        let seconds = Double(audio(for: slot).count) / Double(rate)
        let reached = [4.0, 8.0, 15.0].filter { seconds + 0.00001 >= $0 }.count
        guard reached > milestones[slot, default: 0] else { return false }
        milestones[slot] = reached
        return true
    }
}

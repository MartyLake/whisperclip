import Foundation

struct VoiceProfileVectors: Sendable {
    let id: UUID
    let name: String
    let samples: [[Float]]
}

struct VoiceMatcher {
    static func assign(slots: [Int: [Float]], profiles: [VoiceProfileVectors], locked: [Int: UUID],
                       threshold: Float = Voice_Match_Threshold,
                       margin: Float = Voice_Match_Margin) -> [Int: (profileID: UUID, score: Float)] {
        var candidates: [(Int, UUID, Float)] = []
        for (slot, vector) in slots where locked[slot] == nil {
            var scores: [(UUID, Float)] = []
            for profile in profiles {
                let score = profile.samples.map { cosine(vector, $0) }.max() ?? 0
                scores.append((profile.id, score))
            }
            scores.sort { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0.uuidString < rhs.0.uuidString }
                return lhs.1 > rhs.1
            }
            guard let best = scores.first, best.1 >= threshold,
                  best.1 - (scores.dropFirst().first?.1 ?? 0) >= margin else { continue }
            candidates.append((slot, best.0, best.1))
        }
        var taken = Set(locked.values)
        var result: [Int: (profileID: UUID, score: Float)] = [:]
        for (slot, id, score) in candidates.sorted(by: { $0.2 == $1.2 ? $0.0 < $1.0 : $0.2 > $1.2 }) {
            if taken.insert(id).inserted { result[slot] = (id, score) }
        }
        return result
    }
}

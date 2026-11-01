import Foundation

enum IdentityEvent: Sendable {
    case matched(slot: Int, profileID: UUID, name: String, score: Float)
}

actor VoiceIdentityTracker {
    private var collector = VoiceSampleCollector()
    private let embedder: any SpeakerEmbedder
    private var profiles: [VoiceProfileVectors]
    private var embeddings: [Int: [Float]] = [:]
    private var locked: [Int: UUID] = [:]
    private var labels: [Int: String] = [:]
    private var updating = false
    private var openTurn: SpeakerTurn?
    private var observedThrough: Double = 0

    init(embedder: any SpeakerEmbedder, profiles: [VoiceProfileVectors]) {
        self.embedder = embedder
        self.profiles = profiles
    }

    func appendAudio(_ samples: [Float], at time: Double) { collector.appendAudio(samples, at: time) }
    func refreshProfiles(_ profiles: [VoiceProfileVectors]) { self.profiles = profiles }
    func lock(slot: Int, profileID: UUID?, name: String) {
        locked[slot] = profileID
        labels[slot] = name
    }
    func unlock(slot: Int) { locked[slot] = nil; labels[slot] = nil }

    func snapshot() -> [MeetingVoice] {
        collector.speechSeconds.keys.sorted().map { slot in
            MeetingVoice(slot: slot, label: labels[slot] ?? "Speaker \(slot + 1)",
                         embedding: collector.speechSeconds[slot, default: 0] >= 5 ? embeddings[slot] : nil,
                         speechSeconds: collector.speechSeconds[slot, default: 0], profileID: locked[slot])
        }
    }

    func update(timeline: SpeakerTimelineWindow, final: Bool = false) async -> [IdentityEvent] {
        guard !updating else { return [] }
        updating = true
        defer { updating = false }
        var turns = timeline.turns(from: timeline.startTime, to: timeline.coveredThrough)
        if let open = openTurn,
           let index = turns.firstIndex(where: {
               $0.slot == open.slot && $0.startSeconds <= open.endSeconds + 0.2
                   && $0.endSeconds >= open.endSeconds - 0.01
           }) {
            turns[index] = SpeakerTurn(slot: open.slot, startSeconds: open.startSeconds, endSeconds: turns[index].endSeconds)
        }
        // Consume only newly extended or newly closed turns. Preserve the original
        // start of a long open turn as the rolling timeline window moves forward.
        collector.consume(turns.filter { $0.endSeconds > observedThrough - 0.01 })
        observedThrough = timeline.coveredThrough
        openTurn = turns.last.flatMap { turn in
            turn.endSeconds >= timeline.coveredThrough - 0.2 && !final ? turn : nil
        }
        var embedded = false
        for slot in collector.speechSeconds.keys.sorted() where collector.readyForEmbedding(slot: slot) {
            await embed(slot: slot)
            embedded = true
        }
        if embedded {
            for (slot, vector) in embeddings {
                for (index, profile) in profiles.enumerated() {
                    let score = profile.samples.map { cosine(vector, $0) }.max() ?? 0
                    Logger.log("Voice score slot=\(slot) profileIndex=\(index) score=\(score)", log: Logger.general)
                }
            }
        }
        let matches = VoiceMatcher.assign(slots: embeddings.filter { labels[$0.key] == nil }, profiles: profiles, locked: locked)
        return matches.keys.sorted().compactMap { slot in
            guard let match = matches[slot], let profile = profiles.first(where: { $0.id == match.profileID }) else { return nil }
            locked[slot] = profile.id
            labels[slot] = profile.name
            return .matched(slot: slot, profileID: profile.id, name: profile.name, score: match.score)
        }
    }

    func finish() async -> [MeetingVoice] {
        for slot in collector.speechSeconds.keys.sorted() { await embed(slot: slot) }
        return snapshot()
    }

    private func embed(slot: Int) async {
        let audio = collector.audio(for: slot)
        guard audio.count >= 4_800 else { return }
        do {
            let vector = try await embedder.embed(audio)
            guard vector.count == 192, vector.allSatisfy({ $0.isFinite }) else { return }
            embeddings[slot] = vector
        } catch {
            Logger.log("Voice embedding failed for slot \(slot)" + (GenericHelper.logSensitiveData() ? ": \(error)" : ""),
                       log: Logger.general, type: .error)
        }
    }
}

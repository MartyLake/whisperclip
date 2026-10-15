import XCTest
@testable import WhisperClip

@MainActor
final class SpeakerRenameTests: XCTestCase {
    func testSavedRenameMergeAndMissingEmbedding() async throws {
        let suite = "RenameTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = MeetingStorage(defaults: defaults)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("voices.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let profiles = VoiceProfileStore(fileURL: url, meetingStorage: storage)
        let session = MeetingSession(storage: storage, voiceProfiles: profiles)
        var meeting = storage.create()
        meeting.segments = [MeetingSegment(speaker: .labeled("Speaker 1"), text: "A", startTime: 0, endTime: 6),
                            MeetingSegment(speaker: .labeled("Speaker 2"), text: "B", startTime: 6, endTime: 12),
                            MeetingSegment(speaker: .me, text: "Me", startTime: 12, endTime: 14)]
        meeting.voices = [MeetingVoice(slot: 0, label: "Speaker 1", embedding: voiceVector(0), speechSeconds: 6),
                          MeetingVoice(slot: 1, label: "Speaker 2", embedding: voiceVector(1), speechSeconds: 6)]
        storage.update(meeting)
        let result = try await session.renameSpeaker(meetingID: meeting.id, currentLabel: "Speaker 1", to: " Alice ")
        XCTAssertEqual(result, "Voice saved")
        _ = try await session.renameSpeaker(meetingID: meeting.id, currentLabel: "Speaker 2", to: "ALICE")
        XCTAssertEqual(profiles.profiles.count, 1)
        XCTAssertEqual(profiles.profiles[0].samples.count, 2)
        let renamed = try XCTUnwrap(storage.getMeeting(meeting.id))
        XCTAssertEqual(renamed.segments.map(\.speaker), [.labeled("Alice"), .labeled("Alice"), .me])
        XCTAssertTrue(renamed.voices.allSatisfy { $0.label == "Alice" })
        let before = profiles.profiles.count
        _ = try await session.renameSpeaker(meetingID: meeting.id, currentLabel: "Me", to: "X")
        _ = try await session.renameSpeaker(meetingID: meeting.id, currentLabel: "Alice", to: "  ")
        XCTAssertEqual(profiles.profiles.count, before)
        var short = storage.create()
        short.segments = [MeetingSegment(speaker: .labeled("Speaker 1"), text: "short", startTime: 0, endTime: 1)]
        storage.update(short)
        let shortResult = try await session.renameSpeaker(meetingID: short.id, currentLabel: "Speaker 1", to: "B")
        XCTAssertTrue(shortResult.contains("without voice"))
        XCTAssertNil(profiles.profile(named: "B"))
        XCTAssertEqual(storage.getMeeting(short.id)?.segments.first?.speaker, .labeled("B"))
    }

    func testRelabelLiveRowsAndFutureResolution() {
        let session = MeetingSession(meetingId: UUID()) { _, _ in }
        let row = MeetingSegment(speaker: .pending, text: "a", startTime: 0, endTime: 1, isPending: true)
        session.addPendingSegment(row)
        session.finalizeSegment(id: row.id, text: "a", speaker: .labeled("Speaker 1"))
        let mic = MeetingSegment(speaker: .me, text: "mic", startTime: 1, endTime: 2)
        session.addPendingSegment(mic)
        session.relabelSpeaker(slot: 0, to: "Alice")
        session.relabelSpeaker(slot: 0, to: "Alice")
        XCTAssertEqual(row.speaker, .labeled("Alice"))
        XCTAssertEqual(mic.speaker, .me)
        XCTAssertEqual(session.displaySpeaker(.labeled("Speaker 1")), .labeled("Alice"))
    }

    func testOldMeetingDecodeAndVoiceRoundTrip() throws {
        var note = MeetingNote()
        let data = try JSONEncoder().encode(note)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "voices")
        let old = try JSONDecoder().decode(MeetingNote.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(old.voices.isEmpty)
        note.voices = [MeetingVoice(slot: 0, label: "A", embedding: voiceVector(0), speechSeconds: 6)]
        let decoded = try JSONDecoder().decode(MeetingNote.self, from: JSONEncoder().encode(note))
        XCTAssertEqual(decoded.voices, note.voices)
    }
    func testDeletedLiveEmbeddingCannotBeRestoredBySnapshot() throws {
        let suite = "LiveErasureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = MeetingStorage(defaults: defaults)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("voices.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let profiles = VoiceProfileStore(fileURL: url, meetingStorage: storage)
        let profile = try profiles.addSample(voiceVector(0), toProfileNamed: "A")
        let meeting = storage.create()
        let session = MeetingSession(storage: storage, voiceProfiles: profiles, meetingID: meeting.id)
        let snapshot = [MeetingVoice(slot: 0, label: "A", embedding: voiceVector(0), speechSeconds: 8, profileID: profile.id)]
        session.updateVoices(snapshot)
        try profiles.delete(profile.id)
        session.updateVoices(snapshot)
        XCTAssertNil(storage.getMeeting(meeting.id)?.voices.first?.embedding)
        try profiles.deleteAll()
        session.updateVoices([MeetingVoice(slot: 1, label: "Speaker 2", embedding: voiceVector(1), speechSeconds: 8)])
        XCTAssertNil(storage.getMeeting(meeting.id)?.voices.first?.embedding)
    }

}

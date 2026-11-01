import XCTest
@testable import WhisperClip

func voiceVector(_ index: Int) -> [Float] {
    var vector = [Float](repeating: 0, count: 192)
    vector[index] = 1
    return vector
}

@MainActor
final class VoiceProfileStoreTests: XCTestCase {
    func testRoundTripPermissionsDedupAndCap() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("voices.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = VoiceProfileStore(fileURL: url)
        let first = try store.addSample(voiceVector(0), toProfileNamed: " Alice ")
        _ = try store.addSample(voiceVector(0), toProfileNamed: "alice")
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.profiles[0].samples.count, 1)
        for index in 1...21 { _ = try store.addSample(voiceVector(index), toProfileNamed: "Alice") }
        XCTAssertEqual(store.profiles[0].samples.count, 20)
        XCTAssertEqual(store.profiles[0].samples.first, voiceVector(2))
        let loaded = VoiceProfileStore(fileURL: url)
        XCTAssertEqual(loaded.profile(named: "ALICE")?.id, first.id)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testMergeAndDeleteClearMeetingCopies() throws {
        let suite = "VoiceTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = MeetingStorage(defaults: defaults)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("voices.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = VoiceProfileStore(fileURL: url, meetingStorage: storage)
        let a = try store.addSample(voiceVector(0), toProfileNamed: "A")
        let b = try store.addSample(voiceVector(1), toProfileNamed: "B")
        var meeting = storage.create()
        meeting.voices = [MeetingVoice(slot: 0, label: "A", embedding: voiceVector(0), speechSeconds: 8, profileID: a.id)]
        storage.update(meeting)
        try store.rename(a.id, to: "b")
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.profiles.first?.samples.count, 2)
        XCTAssertEqual(storage.getMeeting(meeting.id)?.voices.first?.profileID, b.id)
        try store.delete(b.id)
        XCTAssertNil(storage.getMeeting(meeting.id)?.voices.first?.embedding)
        XCTAssertEqual(storage.getMeeting(meeting.id)?.voices.first?.label, "A")
        meeting = try XCTUnwrap(storage.getMeeting(meeting.id))
        meeting.voices[0].embedding = voiceVector(2)
        storage.update(meeting)
        try store.deleteAll()
        XCTAssertNil(storage.getMeeting(meeting.id)?.voices.first?.embedding)
    }

    func testCorruptionAndInvalidSample() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("voices.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("broken".utf8).write(to: url)
        let store = VoiceProfileStore(fileURL: url)
        XCTAssertTrue(store.profiles.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathExtension("bak").path))
        XCTAssertThrowsError(try store.addSample([1, 0], toProfileNamed: "A"))
    }
}

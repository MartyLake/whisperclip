import Foundation
import Combine

struct VoiceProfile: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var samples: [[Float]]
    let createdAt: Date
    var updatedAt: Date
}

@MainActor
final class VoiceProfileStore: ObservableObject {
    static let shared = VoiceProfileStore()
    @Published private(set) var profiles: [VoiceProfile] = []
    private(set) var mergedProfileIDs: [UUID: UUID] = [:]
    private(set) var deletedProfileIDs = Set<UUID>()
    private(set) var lastErasedAt: Date?
    private let fileURL: URL
    private let meetingStorage: MeetingStorage?

    init(fileURL: URL? = nil, meetingStorage: MeetingStorage? = nil) {
        self.meetingStorage = meetingStorage
        self.fileURL = fileURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhisperClip", isDirectory: true).appendingPathComponent("voice_profiles.json")
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else { return }
        do {
            profiles = try JSONDecoder().decode([VoiceProfile].self, from: Data(contentsOf: self.fileURL))
            try protect(self.fileURL)
        } catch {
            do {
                let backup = self.fileURL.appendingPathExtension("bak")
                try FileManager.default.copyItem(at: self.fileURL, to: backup)
                try protect(backup)
            } catch { Logger.log("Could not preserve corrupt voice profile backup", log: Logger.general, type: .error) }
            Logger.log("Could not decode voice profiles", log: Logger.general, type: .error)
        }
    }

    var vectors: [VoiceProfileVectors] {
        profiles.map { VoiceProfileVectors(id: $0.id, name: $0.name, samples: $0.samples) }
    }

    func profile(named name: String) -> VoiceProfile? {
        profiles.first { $0.name.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }
    }

    @discardableResult
    func addSample(_ sample: [Float], toProfileNamed name: String) throws -> VoiceProfile {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, sample.count == 192, sample.allSatisfy({ $0.isFinite }),
              sample.contains(where: { $0 != 0 }) else { throw VoiceProfileError.invalidSample }
        var updated = profiles
        let id = profile(named: name)?.id ?? UUID()
        if !updated.contains(where: { $0.id == id }) {
            updated.append(VoiceProfile(id: id, name: name, samples: [], createdAt: Date(), updatedAt: Date()))
        }
        let index = updated.firstIndex { $0.id == id }!
        if !updated[index].samples.contains(where: { cosine($0, sample) >= 0.999 }) {
            updated[index].samples.append(sample)
            updated[index].samples = Array(updated[index].samples.suffix(20))
        }
        updated[index].updatedAt = Date()
        try persist(updated)
        return updated[index]
    }

    func rename(_ id: UUID, to name: String) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if let target = profile(named: name), target.id != id { try merge(id, into: target.id); return }
        var updated = profiles
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].name = name
        updated[index].updatedAt = Date()
        try persist(updated)
    }

    func merge(_ source: UUID, into target: UUID) throws {
        guard source != target, let from = profiles.first(where: { $0.id == source }),
              let index = profiles.firstIndex(where: { $0.id == target }) else { return }
        var updated = profiles
        for sample in from.samples where !updated[index].samples.contains(where: { cosine($0, sample) >= 0.999 }) {
            updated[index].samples.append(sample)
        }
        updated[index].samples = Array(updated[index].samples.suffix(20))
        updated[index].updatedAt = Date()
        updated.removeAll { $0.id == source }
        try persist(updated)
        mergedProfileIDs[source] = target
        (meetingStorage ?? MeetingStorage.shared).relinkVoiceProfile(source, to: target)
    }

    func delete(_ id: UUID) throws {
        try removeBackup()
        try persist(profiles.filter { $0.id != id })
        deletedProfileIDs.insert(id)
        (meetingStorage ?? MeetingStorage.shared).clearVoiceEmbeddings(profileID: id)
    }

    func deleteAll() throws {
        try removeBackup()
        try persist([])
        lastErasedAt = Date()
        (meetingStorage ?? MeetingStorage.shared).clearAllVoiceEmbeddings()
    }

    private func removeBackup() throws {
        let backup = fileURL.appendingPathExtension("bak")
        if FileManager.default.fileExists(atPath: backup.path) { try FileManager.default.removeItem(at: backup) }
    }

    private func protect(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        // Volumes without data protection reject this with EINVAL; the permissions above still apply.
        do {
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        } catch {
            Logger.log("File protection unavailable for voice profiles on this volume", log: Logger.general)
        }
    }

    private func persist(_ updated: [VoiceProfile]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(updated)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        try protect(fileURL)
        profiles = updated
    }
}

enum VoiceProfileError: LocalizedError {
    case invalidSample
    var errorDescription: String? { "The voice sample or profile name is invalid." }
}

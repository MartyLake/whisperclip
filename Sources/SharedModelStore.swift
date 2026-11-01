import Foundation
import Darwin

@_silgen_name("mbr_gid_to_uuid")
private func mbr_gid_to_uuid(_ gid: gid_t, _ uuid: UnsafeMutablePointer<UInt8>) -> Int32

enum SharedModelStoreError: LocalizedError {
    case unavailable(String)
    case lockTimeout

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return "Shared model storage is unavailable: \(reason)"
        case .lockTimeout: return "Timed out waiting for another user to finish a model operation."
        }
    }
}

/// Machine-wide model storage. The ACL lets every local `staff` user update shared models.
final class SharedModelStore: @unchecked Sendable {
    static let shared = SharedModelStore(root: URL(fileURLWithPath: Shared_Models_Root, isDirectory: true))

    let root: URL
    var fluidAudioRoot: URL { root.appendingPathComponent("FluidAudio", isDirectory: true) }
    var downloaderBase: URL { root }
    private var locksRoot: URL { root.appendingPathComponent(".locks", isDirectory: true) }

    init(root: URL) { self.root = root }

    @discardableResult
    func prepare() throws -> URL {
        let fm = FileManager.default
        if !fm.fileExists(atPath: root.path) {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            try setSharedACL(at: root)
        } else if !hasStaffACL(at: root) {
            var info = stat()
            guard lstat(root.path, &info) == 0, info.st_uid == geteuid() else {
                throw SharedModelStoreError.unavailable("the folder is owned by another user")
            }
            try setSharedACL(at: root)
            Logger.log("Repaired shared model storage access control", log: Logger.general)
        }

        for directory in [root.appendingPathComponent("models", isDirectory: true), fluidAudioRoot, locksRoot] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var rootURL = root
        try rootURL.setResourceValues(values)
        return root
    }

    @discardableResult
    func repairPermissions(at directory: URL) throws -> Int {
        var repaired = 0
        let fm = FileManager.default
        var items = [directory]
        if let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) {
            items.append(contentsOf: enumerator.compactMap { $0 as? URL })
        }
        for item in items {
            if (try? item.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { continue }
            var info = stat()
            guard lstat(item.path, &info) == 0, info.st_uid == geteuid(), !hasInheritedStaffACL(at: item) else { continue }
            try setSharedACL(at: item)
            repaired += 1
        }
        Logger.log("Repaired shared model permissions for \(repaired) items", log: Logger.general)
        return repaired
    }

    func withExclusiveLock<T>(model: String, timeout: Duration = .seconds(600), onWait: () -> Void = {}, _ body: () async throws -> T) async throws -> T {
        try FileManager.default.createDirectory(at: locksRoot, withIntermediateDirectories: true)
        let lockName = model.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        let lockURL = locksRoot.appendingPathComponent(String(lockName) + ".lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP)
        guard descriptor >= 0 else { throw SharedModelStoreError.unavailable("could not create model lock") }
        defer { _ = flock(descriptor, LOCK_UN); _ = close(descriptor) }

        let start = ContinuousClock.now
        var notified = false
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            if errno != EWOULDBLOCK && errno != EAGAIN { throw SharedModelStoreError.unavailable("could not acquire model lock") }
            if !notified { onWait(); notified = true }
            guard start.duration(to: .now) < timeout else { throw SharedModelStoreError.lockTimeout }
            try await Task.sleep(for: .milliseconds(100))
        }
        return try await body()
    }

    func withExclusiveLockSync<T>(model: String, timeoutSeconds: TimeInterval = 600, _ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: locksRoot, withIntermediateDirectories: true)
        let lockName = model.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        let lockURL = locksRoot.appendingPathComponent(String(lockName) + ".lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP)
        guard descriptor >= 0 else { throw SharedModelStoreError.unavailable("could not create model lock") }
        defer { _ = flock(descriptor, LOCK_UN); _ = close(descriptor) }
        let start = Date()
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN else { throw SharedModelStoreError.unavailable("could not acquire model lock") }
            guard Date().timeIntervalSince(start) < timeoutSeconds else { throw SharedModelStoreError.lockTimeout }
            usleep(100_000)
        }
        return try body()
    }

    private func hasStaffACL(at url: URL) -> Bool {
        let text = aclText(at: url)
        return containsStaffACE(text) && text.contains("file_inherit") && text.contains("directory_inherit")
    }
    private func hasInheritedStaffACL(at url: URL) -> Bool {
        containsStaffACE(aclText(at: url))
    }

    private func containsStaffACE(_ text: String) -> Bool {
        text.contains("group:staff") || text.contains(":staff:")
    }

    private func aclText(at url: URL) -> String {
        guard let acl = acl_get_file(url.path, ACL_TYPE_EXTENDED) else { return "" }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var length: ssize_t = 0
        guard let text = acl_to_text(acl, &length) else { return "" }
        defer { acl_free(text) }
        return String(cString: text)
    }

    private func setSharedACL(at url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw SharedModelStoreError.unavailable("could not inspect model item") }
        let isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
        var acl: acl_t? = acl_get_file(url.path, ACL_TYPE_EXTENDED) ?? acl_init(1)
        guard let currentACL = acl else { throw SharedModelStoreError.unavailable("could not read access control list") }
        defer { if let acl { acl_free(UnsafeMutableRawPointer(acl)) } }
        var newEntry: acl_entry_t?
        guard acl_create_entry(&acl, &newEntry) == 0, let newEntry,
              acl_set_tag_type(newEntry, ACL_EXTENDED_ALLOW) == 0 else {
            throw SharedModelStoreError.unavailable("could not add shared access control entry")
        }
        guard let staff = getgrnam("staff") else { throw SharedModelStoreError.unavailable("staff group is unavailable") }
        var groupUUID = [UInt8](repeating: 0, count: 16)
        guard groupUUID.withUnsafeMutableBufferPointer({ buffer in
            mbr_gid_to_uuid(staff.pointee.gr_gid, buffer.baseAddress!)
        }) == 0,
              groupUUID.withUnsafeBufferPointer({ acl_set_qualifier(newEntry, $0.baseAddress) }) == 0 else {
            throw SharedModelStoreError.unavailable("could not resolve staff group")
        }
        var permissions: acl_permset_t?
        guard acl_get_permset(newEntry, &permissions) == 0, let permissions,
              acl_clear_perms(permissions) == 0 else {
            throw SharedModelStoreError.unavailable("could not prepare shared access permissions")
        }
        let rights: [acl_perm_t] = isDirectory
            ? [ACL_LIST_DIRECTORY, ACL_ADD_FILE, ACL_SEARCH, ACL_ADD_SUBDIRECTORY, ACL_DELETE_CHILD,
               ACL_READ_ATTRIBUTES, ACL_WRITE_ATTRIBUTES, ACL_READ_EXTATTRIBUTES, ACL_WRITE_EXTATTRIBUTES, ACL_READ_SECURITY]
            : [ACL_READ_DATA, ACL_WRITE_DATA, ACL_APPEND_DATA, ACL_EXECUTE, ACL_DELETE,
               ACL_READ_ATTRIBUTES, ACL_WRITE_ATTRIBUTES, ACL_READ_EXTATTRIBUTES, ACL_WRITE_EXTATTRIBUTES, ACL_READ_SECURITY]
        for right in rights where acl_add_perm(permissions, right) != 0 {
            throw SharedModelStoreError.unavailable("could not set shared access permissions")
        }
        guard acl_set_permset(newEntry, permissions) == 0 else {
            throw SharedModelStoreError.unavailable("could not apply shared access permissions")
        }
        if isDirectory {
            var flags: acl_flagset_t?
            let entryPointer = UnsafeMutableRawPointer(newEntry)
            guard acl_get_flagset_np(entryPointer, &flags) == 0, let flags,
                  acl_add_flag_np(flags, ACL_ENTRY_FILE_INHERIT) == 0,
                  acl_add_flag_np(flags, ACL_ENTRY_DIRECTORY_INHERIT) == 0,
                  acl_set_flagset_np(entryPointer, flags) == 0 else {
                throw SharedModelStoreError.unavailable("could not set ACL inheritance")
            }
        }
        guard acl_set_file(url.path, ACL_TYPE_EXTENDED, acl ?? currentACL) == 0 else {
            throw SharedModelStoreError.unavailable(String(cString: strerror(errno)))
        }
    }
}

enum ModelLocations {
    static let root = resolve(sharedStore: .shared, fallback: GenericHelper.getAppSupportDirectory())
    static let store: SharedModelStore = isShared ? .shared : SharedModelStore(root: root)

    static func resolve(sharedStore: SharedModelStore, fallback: URL) -> URL {
        do { return try sharedStore.prepare() }
        catch {
            Logger.log("Shared model storage unavailable; using per-user model storage", log: Logger.general, type: .error)
            return fallback
        }
    }

    static var fluidAudio: URL {
        if isShared {
            return root.appendingPathComponent("FluidAudio", isDirectory: true).appendingPathComponent("Models", isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FluidAudio/Models", isDirectory: true)
    }
    static var isShared: Bool { root.path == SharedModelStore.shared.root.path }
}

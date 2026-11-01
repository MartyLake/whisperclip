import Foundation

/// Maps monotonic wall time to capture seconds, including time after capture stalls.
final class CaptureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var offset: TimeInterval?

    func observe(captureTime: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        if offset == nil { offset = ProcessInfo.processInfo.systemUptime - captureTime }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        offset = nil
    }

    var now: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard let offset else { return 0 }
        return ProcessInfo.processInfo.systemUptime - offset
    }
}

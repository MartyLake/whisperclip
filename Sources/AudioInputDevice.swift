import Foundation
import AVFoundation
import CoreAudio

/// The input device and format a microphone engine is bound to.
struct MicrophoneRoute: Equatable, CustomStringConvertible {
    let deviceID: AudioDeviceID
    let deviceName: String
    let sampleRate: Double
    let channelCount: AVAudioChannelCount

    var description: String {
        "'\(deviceName)' (id \(deviceID), \(Int(sampleRate)) Hz, \(channelCount) ch)"
    }

    /// Core Audio reports 0 Hz / 0 channels while a device is switching; installing a tap
    /// with such a format raises an Objective-C exception.
    var isUsable: Bool {
        sampleRate > 0 && channelCount > 0
    }

    static func current(format: AVAudioFormat) -> MicrophoneRoute {
        let deviceID = DefaultInputDevice.currentID() ?? AudioDeviceID(kAudioObjectUnknown)
        return MicrophoneRoute(
            deviceID: deviceID,
            deviceName: DefaultInputDevice.name(of: deviceID) ?? "unknown",
            sampleRate: format.sampleRate,
            channelCount: format.channelCount
        )
    }
}

/// Decides when microphone capture has to be rebuilt.
enum MicrophoneRecovery {
    /// Delays before each restart attempt. The first one also coalesces notification bursts.
    static let restartDelays: [Duration] = [.milliseconds(300), .milliseconds(700), .milliseconds(1500), .seconds(3)]
    /// Bluetooth microphones can take a few seconds to deliver their first buffer.
    static let stallThreshold: TimeInterval = 5

    /// Starting an engine can itself post a configuration change, so a running engine is
    /// rebuilt only if the route really moved.
    static func shouldRestart(active: MicrophoneRoute?, current: MicrophoneRoute, isEngineRunning: Bool) -> Bool {
        !isEngineRunning || active != current
    }

    static func isStalled(secondsSinceLastBuffer: TimeInterval) -> Bool {
        secondsSinceLastBuffer >= stallThreshold
    }
}

/// Tracks when audio last arrived. Written from the audio thread, read from the main actor.
final class CaptureHeartbeat: @unchecked Sendable {
    private let lock = NSLock()
    private var lastBeat = ProcessInfo.processInfo.systemUptime

    func beat(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lock.lock()
        defer { lock.unlock() }
        lastBeat = time
    }

    func secondsSinceLastBeat(now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return now - lastBeat
    }
}

enum DefaultInputDevice {
    private static let address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    static func currentID() -> AudioDeviceID? {
        var address = address
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    static func name(of deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    /// Calls `onChange` on a private queue whenever the system default input changes.
    final class Monitor {
        private let queue = DispatchQueue(label: "com.whisperclip.defaultInputDevice")
        private let listener: AudioObjectPropertyListenerBlock

        init(onChange: @escaping @Sendable () -> Void) {
            listener = { _, _ in onChange() }
            var address = DefaultInputDevice.address
            let status = AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, queue, listener
            )
            if status != noErr {
                Logger.log("Failed to observe default input device: \(status)", log: Logger.audio, type: .error)
            }
        }

        deinit {
            var address = DefaultInputDevice.address
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, queue, listener
            )
        }
    }
}

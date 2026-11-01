import XCTest
@testable import WhisperClip

final class AudioInputDeviceTests: XCTestCase {
    private let builtIn = MicrophoneRoute(deviceID: 1, deviceName: "Built-in", sampleRate: 48000, channelCount: 1)
    private let headset = MicrophoneRoute(deviceID: 2, deviceName: "Headset", sampleRate: 24000, channelCount: 1)

    func testRunningEngineOnSameRouteIsNotRestarted() {
        XCTAssertFalse(MicrophoneRecovery.shouldRestart(active: builtIn, current: builtIn, isEngineRunning: true))
    }

    func testStoppedEngineIsRestartedEvenOnSameRoute() {
        XCTAssertTrue(MicrophoneRecovery.shouldRestart(active: builtIn, current: builtIn, isEngineRunning: false))
    }

    func testRunningEngineIsRestartedWhenDeviceChanges() {
        XCTAssertTrue(MicrophoneRecovery.shouldRestart(active: builtIn, current: headset, isEngineRunning: true))
    }

    func testRunningEngineIsRestartedWhenFormatChanges() {
        let bluetoothCallMode = MicrophoneRoute(deviceID: 1, deviceName: "Built-in", sampleRate: 16000, channelCount: 1)
        XCTAssertTrue(MicrophoneRecovery.shouldRestart(active: builtIn, current: bluetoothCallMode, isEngineRunning: true))
    }

    func testRouteIsUnusableWhileDeviceSwitches() {
        XCTAssertTrue(builtIn.isUsable)
        XCTAssertFalse(MicrophoneRoute(deviceID: 1, deviceName: "x", sampleRate: 0, channelCount: 1).isUsable)
        XCTAssertFalse(MicrophoneRoute(deviceID: 1, deviceName: "x", sampleRate: 48000, channelCount: 0).isUsable)
    }

    func testStallDetectionUsesThreshold() {
        XCTAssertFalse(MicrophoneRecovery.isStalled(secondsSinceLastBuffer: MicrophoneRecovery.stallThreshold - 0.1))
        XCTAssertTrue(MicrophoneRecovery.isStalled(secondsSinceLastBuffer: MicrophoneRecovery.stallThreshold))
    }

    func testHeartbeatMeasuresTimeSinceLastBeat() {
        let heartbeat = CaptureHeartbeat()
        heartbeat.beat(at: 100)
        XCTAssertEqual(heartbeat.secondsSinceLastBeat(now: 103.5), 3.5, accuracy: 0.0001)
        heartbeat.beat(at: 103.5)
        XCTAssertEqual(heartbeat.secondsSinceLastBeat(now: 104), 0.5, accuracy: 0.0001)
    }
}

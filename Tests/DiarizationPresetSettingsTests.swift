import XCTest
import SwiftData
@testable import WhisperClip

@MainActor
final class DiarizationPresetSettingsTests: XCTestCase {
    private let suite = "com.whisperclip.tests.diarization-preset.\(UUID().uuidString)"

    func testDefaultPresetIsFast32AndPersistsChanges() {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = SettingsStore(defaults: defaults, container: SettingsDataContainer.create(inMemory: true))
        XCTAssertEqual(store.nemotron3Preset, .fast32)
        store.nemotron3Preset = .fast
        XCTAssertEqual(defaults.string(forKey: "nemotron3Preset"), "fast")
        defaults.removePersistentDomain(forName: suite)
    }

    func testUnknownStoredPresetFallsBackToFast32() {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set("future-preset", forKey: "nemotron3Preset")
        let store = SettingsStore(defaults: defaults, container: SettingsDataContainer.create(inMemory: true))
        XCTAssertEqual(store.nemotron3Preset, .fast32)
        defaults.removePersistentDomain(forName: suite)
    }
}

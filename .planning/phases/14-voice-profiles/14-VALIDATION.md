---
phase: 14
slug: voice-profiles
status: planned
created: 2026-10-15
---

# Phase 14 — Validation Strategy

> Collection, matching, storage, tracker logic and rename semantics are tested with fake embeddings and temp
> files. Whether CAM++ separates real people on call audio, and the threshold, are proven only by Plan 06.

| Property | Value |
|----------|-------|
| **Framework** | XCTest |
| **Quick run** | `swift test --filter VoiceSampleCollectorTests` / `VoiceMatcherTests` / `VoiceProfileStoreTests` / `VoiceIdentityTrackerTests` / `SpeakerRenameTests` |
| **Full suite** | `swift test --parallel` |
| **App build** | `./local_build.sh Debug` |

## Per-Task Verification Map

| Task | Wave | Requirement | Type | Command | Status |
|------|------|-------------|------|---------|--------|
| 01 T1 | 1 | VOICE-02 | Build | `swift build` | ⬜ |
| 01 T2 | 1 | VOICE-02 | Unit (TDD) | `swift test --filter VoiceSampleCollectorTests` | ⬜ |
| 01 T3 | 1 | VOICE-03 | Unit (TDD) | `swift test --filter VoiceMatcherTests` | ⬜ |
| 02 T1 | 1 | VOICE-02, VOICE-04 | Unit (TDD) | `swift test --filter VoiceProfileStoreTests` | ⬜ |
| 02 T2 | 1 | VOICE-02 | Unit (TDD) | `swift test --filter PersistenceTests` | ⬜ |
| 03 T1-T2 | 2 | VOICE-03 | Unit (TDD) | `swift test --filter VoiceIdentityTrackerTests`; `MeetingSessionResolveTests` | ⬜ |
| 03 T3 | 2 | VOICE-03 | Build + suite | `swift test --parallel`; `./local_build.sh Debug` | ⬜ |
| 04 T1 | 3 | VOICE-01, VOICE-02 | Unit (TDD) | `swift test --filter SpeakerRenameTests` | ⬜ |
| 04 T2 | 3 | VOICE-01 | Build | `./local_build.sh Debug` | ⬜ |
| 05 T1 | 3 | VOICE-04 | Build | `./local_build.sh Debug` | ⬜ |
| 06 T1-T2 | 4 | VOICE-01..04 | Manual + calibration | see 14-06-PLAN | ⬜ |

## Security / privacy

- Voice embeddings are biometric data: stored only in `voice_profiles.json` (0600, complete protection) and in
  meeting JSON (`voices`), never logged, never sent anywhere.
- Logs: slot numbers, scores, durations, counts; profile names only with `LOG_SENSITIVE_DATA=1`.
- No network in tests; no model downloads in tests (fake embedder).

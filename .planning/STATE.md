---
gsd_state_version: 1.0
milestone: v1.2
milestone_name: Live Enrichment & Diarization Fix
status: Phase 11.2 complete; true streaming ASR shipped and verified
stopped_at: Phase 11.2 PASS; streaming and full-suite verification accepted
last_updated: "2026-04-19T10:59:42Z"
progress:
  total_phases: 5
  completed_phases: 5
  total_plans: 14
  completed_plans: 14
  percent: 100
---

# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-22)

**Core value:** Точна транскрипція зустрічей з правильною атрибуцією спікерів.
**Current focus:** Phase 13 planning (Reconciler on the Nemotron 3 timeline)

---

## Current Position

Phase: 11.2 (true-streaming-asr) — COMPLETE
Phase: 11.3 (dependency upgrade + Gemma 4 E4B) — COMPLETE 2026-10-13. Closed by owner decision with UAT 6/8 PASS; steps 5-6 (existing LLMs on the new MLX stack) were not run — residual risk recorded in `11.3-UAT.md`
Phase: 11.4 (Nemotron 3 diarizer) — COMPLETE 2026-10-14. UAT PASS (owner). System audio is split into "Speaker N" by Nemotron 3 `fast32`; `DiarizerManager` removed
Next: Phase 13 (Reconciler) — planning

### Resume 2026-10-13 (after pause since 2026-04-20)

- Roadmap revised: inserted 11.3 and 11.4, added 14; execution order 11.3 → 11.4 → 13 → 12 → 14
- Source of the new work: `../stt-diarization` (Radnyk) — Nemotron 3 Diarization, Gemma 4 E4B, voice profiles
- Decisions: Nemotron 3 runs natively via FluidAudio CoreML (no Python sidecar); HF token is requested in the UI because the CoreML model repo is gated; CI is deferred — local build only for now; the old `DiarizerManager` clustering path is retired in 11.4 (owner: it never worked in practice) — no-token fallback is source-based attribution
- Baseline (2026-10-13, Swift 6.3.3 / Xcode 26.6): the untouched branch does NOT build. FluidAudio 0.10.0 fails to compile in its own sources (`StreamingAsrManager.swift:198, 319, 470` — "sending 'asrManager' risks causing data races"), identically via `swift build --target FluidAudio` and via the Xcode app project. WhisperClip's own sources were never reached, so their status is still unknown. Consequence: the FluidAudio upgrade (DEP-03) moves from 11.4 into 11.3
- WhisperKit decision revised (2026-10-13): upgrade to 1.1.1 inside Phase 11.3 as Plan 05 (DEP-04), after the build is green on 0.15.0 and before the manual checkpoint. Reason: 1.x has no `swift-transformers` dependency. Known mismatch to be fixed there: `Package.swift` pins 0.15.0, `project.yml` says 0.18.0
- Phase 11.3 result (2026-10-13): app builds and runs on FluidAudio 0.17.7, `mlx-swift-lm` 3.32.3, WhisperKit 1.1.1 (`argmax-oss-swift`). Finding D-1: FluidAudio 0.17 moved model folders (`parakeet-tdt-0.6b-v3-coreml` → `parakeet-tdt-0.6b-v3`, `speaker-diarization-coreml` → `speaker-diarization`), so upgraded installs must re-download Parakeet and old folders are orphaned; the app does not check STT readiness before recording. Tracked in `IDEAS.md`, unscheduled
- Phase 11.4 planned (2026-10-13). The Nemotron 3 CoreML repo is public, not gated — the HF token work (TOKEN-01..03) is deferred to `IDEAS.md`, reversing the earlier decision to request a token in the UI. Accepted cost: system-audio rows appear ~3 s later than today until Phase 13
- Phase 11.4 result (2026-10-14): Nemotron 3 streaming diarization live. Review caught system-audio loss after ~40 s in `SpeakerBufferManager` (fixed before commit); first live run showed the model never loaded because `Nemotron3Models.load(config:directory:)` does not match the Hub cache layout (fixed `478e5e2`, now `loadFromHuggingFace`). Lesson: unit tests with a mock provider cannot catch model-loading failures — every model integration needs a live check
- Environment (2026-10-14): Xcode 27.0 — needs the Metal Toolchain component (`xcodebuild -downloadComponent MetalToolchain`) or MLX does not compile
- Added `project.yml` + `xcode_gen.sh` (XcodeGen) to open the app as an Xcode app target; generated project lives in `Xcode/` (gitignored)

## Performance Metrics

**Velocity (v1.0 complete):**

- Total plans completed: 14
- v1.0 phases: 5 complete

**v1.1 By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 6. SpeakerBufferManager Actor | TBD | - | - |
| 7. DualChannelAudioCapture | TBD | - | - |
| 8. MeetingRecorder Rewire | TBD | - | - |
| 9. Waveform Color | TBD | - | - |
| 10. Chat Bubble UI | TBD | - | - |

| Phase 06 P01 | 115s | 2 tasks | 4 files |

---
| Phase 06 P02 | 223 | 2 tasks | 3 files |
| Phase 06 P03 | 5min | 2 tasks | 2 files |
| Phase 08 P01 | 8m | 3 tasks | 3 files |
| Phase 08 P02 | 16m | 2 tasks | 2 files |
| Phase 09-waveform-color-per-speaker P01 | 225s | 2 tasks | 3 files |
| Phase 09-waveform-color-per-speaker P00 | 3m | 1 tasks | 3 files |
| Phase 09-waveform-color-per-speaker P03 | 6min | 2 tasks | 4 files |
| Phase 09-waveform-color-per-speaker P04 | 7min | 2 tasks | 2 files |

## Accumulated Context

### v1.0 SettingsView Refactoring — Completed (Phases 1-5)

- Phase 1: UI Decomposition ✓
- Phase 2: ViewModel Extraction ✓
- Phase 3: SwiftData Migration ✓
- Phase 4: Test Coverage (18 tests) ✓
- Phase 5: Hotkey Fix (KeyboardShortcuts 2.4.0, AppDelegate) ✓

### Diarization Debug Session (2026-03-22)

- DiarizerManager wired into MeetingRecorder (was never called before)
- Me label regression fixed: mic audio returns .me immediately, skips diarizer
- clusteringThreshold lowered 0.7 → 0.4 → 0.3 (speakerThreshold 0.84 → 0.48 → 0.36)
- Speaker 2 now detected: distance 0.437 > speakerThreshold 0.36 ✓
- Root problem: resolveSpeaker() returns ONE dominant speaker per chunk — minority speaker lost
- New milestone: full pipeline rewrite — diarization-first, per-speaker buffers, atomic ASR

### Key Decisions (v1.1)

- Hybrid splitting: speaker change trigger + 30s max duration cap (PIPE-02, PIPE-03)
- 0.5s minimum floor: buffers < 8,000 samples discarded without ASR (PIPE-06)
- Colored waveform (not name chip) for real-time speaker feedback (RT-01..03)
- Chat-style bubbles (iMessage) for MeetingDetailView grouping (CHAT-01..04)
- Never reset DiarizerManager between turns — destroys SpeakerManager state
- `SWIFT_STRICT_CONCURRENCY=complete` must be enabled before first line of Phase 6
- Extracted TranscriptionQueue to top-level file in Phase 6 (not Phase 8) to keep actor promotion isolated from pipeline rewiring (06-03)
- TranscriptionQueue uses internal access (not public) — WhisperClip is single-module, no ABI boundary needed (06-03)
- MeetingRecorder updates `activeSpeakerLabel` from `ClosedSpeakerBuffer` arrival before enqueueing ASR work (08-01)
- `stopRecording()` now follows producer stop, consumer join, capture stop, queue drain, then final mic processing to avoid dropping the last speaker turn (08-01)
- MeetingRecorder no longer owns system speaker-label mapping or system-text deduplication; fallback attribution uses `source.speaker` with mic-only deduplication (08-01)
- MeetingRecorder now buffers non-diarized system audio locally and routes 5-second `.system` chunks through `TranscriptionQueue` when the diarizer is unavailable (08-02)
- System audio fallback preserves overflow samples beyond 5 seconds and flushes the remainder during `stopRecording()` to avoid data loss (08-02)
- Use explicit `Color(hex:)` palette entries in `speakerPaletteColor()` so waveform and chat bubbles share deterministic speaker colors (09-01)
- Map empty `activeSpeakerLabel` values to `.unknown` through `Speaker(displayName:)` for idle-state safety (09-01)
- Establish Wave 0 XCTest stubs before implementation waves so filtered test commands are stable and meaningful (09-00)
- Route MeetingWaveformView active bars through `speakerPaletteColor(Speaker(displayName:))` to keep palette identity aligned with chat bubbles (09-03)
- Normalize waveform bar heights using `20*log10` with `-50dB` floor and `2px` minimum for stable low-signal rendering (09-03)
- Set `activeSpeakerLabel` to `Speaker.me.displayName` at mic chunk ingress so waveform color reflects local speech immediately (09-04)
- Lock mic-source identity with regression checks for `Speaker.me.displayName`, `Speaker(displayName:)`, color index, and `AudioSource.microphone.speaker` mapping (09-04)
- TEMP (2026-03-23 11:30 prep): Disable diarization pipeline in `MeetingRecorder`; use continuous source-based streaming path (`mic -> "Me"`, system/non-mic -> `activeSpeakerLabel = ""`) until explicit re-enable decision
- Phase 10 restored mutable transcript segments via `@Observable` `MeetingSegment`, pending/finalize APIs in `MeetingSession`, and in-place transcript row updates without replacing list elements
- Phase 10 re-enabled diarizer processing with 7-second micro-windows, sample-accurate split helpers, and pending transcript finalization for diarized buffers
- Phase 10 UAT is accepted as PASS with known carry-over limitations: transient pending UI can still appear in edge cases, and speaker-boundary quality still needs follow-up in Phases 11 and 12
- Phase 11 added `StreamingTests`, `VoiceToTextProtocol.processStream`, and WhisperKit partial-text callbacks via `TranscriptionProgress.text`
- Phase 11 introduced `Speaker.pending`, fixed `displayText` / `displaySpeaker`, and routed `MeetingRecorder` through `VoiceToTextFactory` for live pending-segment mutation
- Phase 11 updated transcript-row rendering to bind to model display helpers so immediate text and pending speaker state reach the UI without duplicated view logic
- Phase 11.1 added early VAD-driven pending bubbles, `VADStateMachine`, mic-level and diarizer-gated speech callbacks, pending bubble reconciliation, and ghost cleanup
- Phase 11.1 manual validation passed after fixing two edge cases: stale ghost-cleanup task ownership and WhisperKit empty-final-text fallback to `lastPartialText`
- Phase 11.2 added streaming-session lifecycle methods to `VoiceToTextProtocol`, WhisperKit LCP/truncation helpers, priority fragment lanes in `TranscriptionQueue`, Parakeet `StreamingEouAsrManager` sessions, and 300ms microphone fragment wiring in `MeetingRecorder`

### Roadmap Evolution

- **Phase 11.1:** Inserted "Audio-Active Pending State" after Phase 11. Urgent work to decouple visual pending from ASR first-token arrival using VAD/energy gate (200-400ms activity). (URGENT)
- **Phase 11.2:** Inserted "True Streaming ASR" after Phase 11.1. Missed during Phase 11 planning; ensures WhisperKit/Parakeet tokens update in real-time. (URGENT)

### Blockers/Concerns

- Phase 6: diarization polling cadence (100-200ms) unvalidated against CoreML latency on M-series — measure with Instruments before finalizing
- Phase 6: clusteringThreshold=0.3 validated for one scenario; verify on 3+ speaker pairs before Phase 8 integration
- Phase 7: CMSampleBuffer format assumption (32-bit float PCM) needs assertion verified on macOS 14 and 15
- Phase 10 reduced but did not eliminate split-boundary artifacts; watch for occasional start/end truncation or mixed attribution near speaker changes
- Live transcription path now includes true fragment-based microphone streaming and queue-level backpressure. Hardware/manual latency validation for real meeting conditions remains a follow-up check.
- **Swift Concurrency:** Phase 11 implementation leaves multiple strict-concurrency warnings (queue-handoffs) in `MeetingRecorder`. This is a high-priority tech debt that may impact `Reconciler` stability in Phase 13.

---

## Session Continuity

Last session: 2026-04-19T10:59:42Z
Stopped at: Phase 11.2 PASS; next work is Phase 12 planning or hardware validation follow-up
Resume file: None

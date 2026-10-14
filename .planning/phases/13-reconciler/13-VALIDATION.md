---
phase: 13
slug: reconciler
status: planned
created: 2026-10-14
---

# Phase 13 — Validation Strategy

> The Reconciler, the chunker and word-timing mapping are pure and tested with scripted inputs. Whether the
> real ASR returns timings and whether labels are right on real speech is covered only by Plan 05.

| Property | Value |
|----------|-------|
| **Framework** | XCTest |
| **Quick run** | `swift test --filter SpeakerReconcilerTests` / `SystemAudioChunkerTests` / `TimedTranscriptionTests` / `MeetingSessionResolveTests` |
| **Full suite** | `swift test --parallel` |
| **App build** | `./local_build.sh Debug` (Xcode 27 needs the Metal Toolchain component) |

## Per-Task Verification Map

| Task | Wave | Requirement | Type | Command | Status |
|------|------|-------------|------|---------|--------|
| 01 T1-T2 | 1 | REC-02 | Unit (TDD) | `swift test --filter TimedTranscriptionTests` | ⬜ |
| 02 T1-T2 | 1 | REC-01..03 | Unit (TDD) | `swift test --filter SpeakerReconcilerTests` | ⬜ |
| 03 T1 | 1 | REC-01 | Unit (TDD) | `swift test --filter SpeakerBufferManagerTests` | ⬜ |
| 03 T2 | 1 | REC-01 | Unit (TDD) | `swift test --filter SystemAudioChunkerTests` | ⬜ |
| 04 T1 | 2 | REC-02, REC-03 | Unit (TDD) | `swift test --filter MeetingSessionResolveTests` | ⬜ |
| 04 T2 | 2 | REC-01..03 | Build + suite | `swift test --parallel`; `./local_build.sh Debug` | ⬜ |
| 05 T1 | 3 | REC-01..03 | Manual | `11.4`-style live run, see 13-05-PLAN | ⬜ |

## Security / privacy

- No transcript text, word lists or file paths in logs outside `LOG_SENSITIVE_DATA=1` (Reconciler logs ids, counts, times).
- No network in tests; no model downloads.

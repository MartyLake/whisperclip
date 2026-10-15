# 13-04 — Recorder integration

System batches now feed energy VAD + `SystemAudioChunker`, independently of the optional timeline producer. Whole chunks enter the nonblocking serial transcription queue, then timed file ASR. With Nemotron the text remains Pending until the reconciler labels or splits it. Without Nemotron it finalizes as Other. Mic processing retains its source-based Me attribution.

The 250 ms reconciler loop requests only the oldest queued window and skips snapshots when idle. `CaptureClock` maps monotonic wall time to the capture clock, so deadlines advance even when capture stalls. Generation guards prevent stale system work from mutating a later/cancelled session. Nemotron speech callbacks only update active-speaker metadata.

`MeetingSession.resolvePendingSegment` persists only resolved rows, preserves the existing instance for labels, replaces split originals before any storage write, sorts the list, and ignores repeated/stale resolutions. Pending insertion is synchronous on the main actor, including session startup, avoiding a callback/ASR insertion race. Segment time bounds are mutable so onset placeholders receive the actual chunk range. An injectable persistence boundary and recorder dependencies allow deterministic integration tests without touching stored meetings.

Stop order: capture stop → system stream drain → chunker flush → ASR queue drain → cancel/join reconciler polling → timeline finish → reconciler final flush/apply → remove empty onset placeholder → existing mic finalization/drain. Cancel stops reconciliation without applying resolutions.

Removed the closed-speaker-buffer type/stream, buffer queue overload, old turn cutting, diarizer-driven transcription and fixed fallback chunking. `rg` confirms all retired symbols absent from Sources/Tests.

`MeetingSessionResolveTests`: 3 tests for exact persistence counts, original removal, duplicate resolution, sorted interleaved mic rows and missing IDs. Recorder tests exercise the actual stop path with fakes: split after provider.finish, nil-timing majority, and a short final phrase without the model.

UAT remains required for real-model label stability, latency, timing quality, saved/reopened meetings and mic behaviour during remote speech.

## Verification

- `swift test --parallel`: 105 tests passed (arm64, 2026-10-15).
- `./local_build.sh Debug`: succeeded. Repository-wide concurrency and fixture warnings remain; this is not a warning-free build.
- No model downloads or network-backed inference were used in tests.

---
phase: 14-voice-profiles
plan: 03
status: implemented
completed: 2026-10-15
---

Code commit: `2afbf8e` (code and tests only).

# Plan 14-03 execution summary

Implemented VoiceIdentityTracker actor with an injected embedder, capture-clock
ring, milestone embeddings, profile snapshots, locked assignments, match events
and a final embedding pass. Embeddings are persisted only for slots with at least
5 s of speech; an earlier embedding can be used for matching.

MeetingRecorder loads CAM++ alongside Nemotron, feeds system batches and updates
identity from the Reconciler poll task even when no transcript rows are queued.
Matched names relabel existing rows; later Reconciler resolutions map the original
slot label through MeetingSession.speakerNames. Cancel discards the tracker.

Stop order: stop capture and drain batches/ASR, cancel and join polling, stop the
diarizer, flush Reconciler, consume the final identity timeline, perform final
embeddings and persist voices, then finish the microphone work and clean up.
CAM++ load failure leaves recording and text-only renaming available.

Deletion and merging are also reconciled with subsequent live snapshots so an
active recording cannot restore erased vectors or stale merged profile links.
Delete-all suppresses further voice persistence for a meeting already in progress.

Validation: 4 tracker tests, live relabel and privacy-erasure tests passed, as did
the existing recorder regression tests. A 45 s synthetic uninterrupted turn
exercises rolling-window accounting. CPU usage and model latency were not measured;
these require real CAM++ inference in Plan 06. Existing unrelated concurrency
warnings remain; no warnings were found in the new voice components.

Final automated verification: `swift test --parallel` passed all 138 tests
(19 new voice-related tests); `./local_build.sh Debug` succeeded. The profile store
suite was also rerun after the final erasure-order adjustment: 3/3 passed.

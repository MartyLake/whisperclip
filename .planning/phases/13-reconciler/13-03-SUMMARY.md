# 13-03 — Timeline producer and phrase chunks

`SpeakerBufferManager.timelineView(from:)` returns a Sendable capture-time `SpeakerTimelineWindow`; `sessionStartTime` remains nil until the first nonempty batch. Windows retain only frames from 1.2 s before the requested lower bound, preserving nearby-turn fallback and merge context. Existing capture-gap zero padding still feeds the provider. The manager no longer stores audio. Timeline frame rounding tolerates floating-point offset conversion.

`SystemAudioChunker` uses 20 ms RMS frames, a supplied dB threshold, 400 ms trailing silence, a 1 s normal chunk floor, and an 8 s cap cut at the quietest frame in the last second. Leading silence is dropped with its time advanced. Gaps flush the previous tail. Stop/gap tails may be shorter than 1 s and are retained.

Plan clarification: a phrase shorter than 1 s retains enough trailing silence to reach the 1 s ASR minimum. Otherwise cutting strictly at silence onset would either discard it downstream or delay it until the 8 s cap. Longer phrases cut at silence onset as planned.

Tests: 2 timeline producer tests; 6 chunker tests covering pause/minimum/cap/quietest-frame selection, partial frames, flush, gaps, all-silent drop and exact speech sample preservation.

## Verification

- `swift test --parallel`: 105 tests passed (arm64, 2026-10-15).
- `./local_build.sh Debug`: succeeded. Repository-wide concurrency and fixture warnings remain; this is not a warning-free build.
- No model downloads or network-backed inference were used in tests.

# 13-01 — Timed transcription

Implemented `TimedWord`, `TimedTranscription` and `processStreamWithTimings`. The default delegates to the existing streaming method and returns nil words, retaining WhisperKit behaviour. Parakeet has one streaming file-transcription path and maps FluidAudio word timings.

FluidAudio 0.17.7 was inspected locally: `AsrManager+Transcription.processTranscriptionResult` populates `ASRResult.tokenTimings`; `AsrManager+TokenProcessing.createTokenTimings` converts encoder-frame timestamps to seconds from file start, including its emission-delay correction. Empty timing arrays fall back to nil. This is source confirmation; real audio timing quality remains UAT.

`TimedTranscriptionTests` (2 tests) covers subwords, word boundaries, blanks, nil/empty data and default events/text.

## Verification

- `swift test --parallel`: 105 tests passed (arm64, 2026-10-15).
- `./local_build.sh Debug`: succeeded. Repository-wide concurrency and fixture warnings remain; this is not a warning-free build.
- No model downloads or network-backed inference were used in tests.

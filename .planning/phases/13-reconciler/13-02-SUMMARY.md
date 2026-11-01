# 13-02 — Speaker Reconciler

Standalone `SpeakerReconciler` actor accepts capture-time rows and a Sendable timeline interface. It exposes `submit`, `poll`, `flush`, `oldestQueuedStart` and the preset-aware deadline helper. An injected clock makes deadlines deterministic. No audio/model/session/recorder dependency.

| Rule | Test |
|---|---|
| Single speaker, ignore 0.4 s minority, majority without words | testSingleAndMinorityAndMajority |
| Word split preserves sequence and contiguous part ranges | testSplitPreservesWordsAndContiguousTimes |
| Word straddles boundary: greatest overlap wins | testBoundaryWordUsesLargestOverlap |
| Silence: nearest within 1 s, otherwise Other | testSilenceNearAndFar |
| Coverage end + 0.2 s, deadline, final flush, ordered one-time output | testCoverageDeadlineFlushAndOrder |

Inter-word gaps belong to the preceding part so split ranges are contiguous. Equal-overlap ties use ascending slot order deterministically.

## Verification

- `swift test --parallel`: 105 tests passed (arm64, 2026-10-15).
- `./local_build.sh Debug`: succeeded. Repository-wide concurrency and fixture warnings remain; this is not a warning-free build.
- No model downloads or network-backed inference were used in tests.

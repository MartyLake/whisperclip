# Phase 14 — Calibration and UAT

Implementation commit: `2afbf8e`.

Status: READY FOR OWNER VERIFICATION. Plans 01–05 implemented; Plan 06 pending.
No real CAM++ inference, score calibration or manual acceptance is claimed.

Automated evidence: 138/138 tests passed, including 19 new tests; final profile
store rerun 3/3 passed; Debug build succeeded. Existing unrelated strict-concurrency
warnings remain. Model loading, real voice quality, CPU and latency need live UAT.

## Calibration (Plan 06 Task 1)

Run `./local_run.sh Debug` (this script already sets LOG_SENSITIVE_DATA=1 and
LOG_TO_CONSOLE=1). CAM++ downloads on first use when Nemotron is available.

1. Record meeting A with 3+ remote people, at least 5 s clean speech each.
2. Click each speaker header and save a name. Confirm profiles have samples.
3. Record meeting B with the same people and an unknown person if possible.
4. Collect `Voice score slot=… profileIndex=… score=…` lines and identify which
   anonymous slot/profile index pairs belong to the same person. Do not paste
   transcripts, paths, actual names or embedding vectors.
5. Compare the lowest same-person score and highest different-person score;
   choose threshold/margin from their separation. If scores overlap, investigate
   the data rather than claiming a usable threshold.

Current constants: threshold 0.5; margin 0.05 — placeholders, NOT calibrated.

| Meeting | Slot | Profile index | Same person? | Cosine |
|---|---|---|---|---|
| B | pending | pending | pending | pending |

Resume with scores (including anonymous same/different-person attribution).

## Manual verification (Plan 06 Task 2)

| Step | Check | Result |
|---|---|---|
| 1 | Live rename updates earlier and later bubbles | Pending |
| 2 | Saved rename updates every row and adds a sample | Pending |
| 3 | New meeting recognizes enrolled people within roughly 10–20 s of speech | Pending |
| 4 | No false matches between enrolled people; unknown person stays unnamed | Pending |
| 5 | Same-name rename merges speakers/bubbles | Pending |
| 6 | Short speaker can be renamed; voice-not-saved explanation is shown | Pending |
| 7 | Settings list, rename, merge, delete one and delete all | Pending |
| 8 | Unavailable CAM++ / first-run offline still permits recording | Pending |
| 9 | Profile file 0600; only model-download network traffic for voice data | Pending |

Resume with approved steps or observed failures. Phase 14 remains open until the
calibration and manual results are recorded. `14-06-SUMMARY.md` is intentionally
not created as completed.

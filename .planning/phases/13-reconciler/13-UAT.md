# Phase 13 — Manual verification

Status: PASS by owner decision (2026-10-15) — steps 1-8 pass on live system audio; step 9 skipped by owner decision.

Build and launch with `./local_run.sh Debug`. Select Parakeet, use an installed Nemotron fast32 model, and replay the same multi-speaker recording used in Phase 11.4 as system audio.

| Step | Expected | Result |
|---|---|---|
| 1 | Startup log: Nemotron 3 speaker separation enabled | PASS (implied: Speaker N labels appear live, so separation is enabled; log line not checked) |
| 2 | Pending onset <1 s; text ~1 s after phrase end | PASS (owner, after jitter fix `5c80e5a`: phrase-level rows, no `[transcription failed]`; latency not measured) |
| 3 | Speaker N within ~6 s; stable labels | PASS with note — owner: "sometimes not very precise" about the speaker; labels resolve |
| 4 | Fast exchange splits correctly, no missing/repeated words | PASS (owner: "much better" after jitter fix; no missing/repeated words reported) |
| 5 | Mic during remote speech remains Me | PASS (owner: my rows stay Me) |
| 6 | Stop mid-phrase retains tail, no Pending rows | PASS (owner: stop works fine) |
| 7 | Reopened saved meeting matches live rows/labels, no duplicates | PASS (owner: no duplicates, transcript matches) |
| 8 | WhisperKit: labels resolve, rows never split | PASS (owner: works great, recognises Ukrainian better than Parakeet; row splitting not specifically checked) |
| 9 | Without Nemotron: source-based Other rows | SKIPPED — owner decision; requires removing the Nemotron model manually |

Record actual observations per step; report failing steps or approval. Removing a model for step 9 is a manual action and was not performed automatically.

## Jitter fix (live recheck done)

The owner reported fragmented bubbles and repeated `[transcription failed]` rows. Source-level diagnosis confirmed an overly strict capture-gap threshold. Fixed in `5c80e5a`; automated tests (109) and Debug build pass. Repeat steps 2, 4, 6 and 7 with real system audio to confirm phrase-level chunks and absence of invalid-short-audio failures. Live recheck 2026-10-15: PASS (owner) — phrase-level chunks, failures gone.

## Residual risk and observations

- Step 9 (no-Nemotron fallback) not run live; covered only by automated tests.
- Speaker attribution is occasionally imprecise (owner, no pattern reported yet). Candidates if it persists: word-majority instead of start-time resolution, hysteresis for short rows; longer term — post-meeting SpeakerKit refine pass (`IDEAS.md`) and Phase 14 voice profiles.
- Owner observation: WhisperKit recognises Ukrainian better than Parakeet.

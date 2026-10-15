# Phase 13 — Manual verification

Status: awaiting owner run (2026-10-15). Automated tests do not prove live model wiring or latency.

Build and launch with `./local_run.sh Debug`. Select Parakeet, use an installed Nemotron fast32 model, and replay the same multi-speaker recording used in Phase 11.4 as system audio.

| Step | Expected | Result |
|---|---|---|
| 1 | Startup log: Nemotron 3 speaker separation enabled | Pending |
| 2 | Pending onset <1 s; text ~1 s after phrase end | Pending |
| 3 | Speaker N within ~6 s; stable labels | Pending |
| 4 | Fast exchange splits correctly, no missing/repeated words | Pending |
| 5 | Mic during remote speech remains Me | Pending |
| 6 | Stop mid-phrase retains tail, no Pending rows | Pending |
| 7 | Reopened saved meeting matches live rows/labels, no duplicates | Pending |
| 8 | WhisperKit: labels resolve, rows never split | Pending |
| 9 | Without Nemotron: source-based Other rows | Pending |

Record actual observations per step; report failing steps or approval. Removing a model for step 9 is a manual action and was not performed automatically.

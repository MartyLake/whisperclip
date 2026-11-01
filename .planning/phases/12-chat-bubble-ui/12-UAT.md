# Phase 12 — UAT

Status: PASS (owner, 2026-10-15) — all 8 steps on live system audio.

Run `./local_run.sh Debug` with Nemotron fast32 and an STT model. Play a
multi-speaker recording through system audio and speak into the mic occasionally.

| Step | Expected result | Result |
|---|---|---|
| 1 | Remote speech for 20+ s grows one bubble, one name and timestamp | PASS — owner: one bubble grows; when the other person starts talking their part first lands in the same bubble, then splits off. Expected per D-05; owner: fine |
| 2 | Pending phrase is muted and resolves in place | PASS — owner: new phrase starts muted; in-place resolution observed together with step 3 |
| 3 | Speaker change creates a distinct bubble; misattributed pending phrase moves | PASS — owner: new bubble per speaker; misattributed phrase moves over |
| 4 | Mic creates right-aligned blue Me bubble and splits remote turns | PASS — owner: Me on the right |
| 5 | Growing bubble keeps the live view at the bottom | PASS |
| 6 | Saved grouping, selection/copy, stats, summary, Q&A and export work | PASS — owner: all as expected |
| 7 | Speaker colours persist after relaunch | PASS |
| 8 | Several-minute meetings scroll smoothly on both screens | PASS |

## Observations

- D-05 trade-off is visible as designed: at a speaker change, the new speaker's first phrase is shown (muted) in the previous bubble for a few seconds, then moves to its own bubble. Owner accepts it.

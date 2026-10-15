---
phase: 14-voice-profiles
plan: 01
status: implemented
completed: 2026-10-15
---

Code commit: `2afbf8e` (code and tests only).

# Plan 14-01 execution summary

Implemented SpeakerEmbedder, the FluidAudio CAM++ adapter, cosine validation,
VoiceSampleCollector and VoiceMatcher. The collector retains 30 s of capture-clock
system audio, selects trimmed clean turns, replaces samples for growing turns,
keeps at most 15 s per slot and fires the 4/8/15 s milestones once. Three preferred
turns exclude fallback pieces. Growing turns retain their original start as the
rolling timeline window advances; expired audio is skipped without losing already
collected samples.

CAM++ uses CampPlusEmbedder.load -> CampPlusModels.downloadAndLoad. The dependency
caches the public FluidInference/campplus-coreml bundle in Application Support /
FluidAudio / Models / campplus-coreml; its own loader checks and reuses that cache.
No Hugging Face token or Python runtime is required. Informational FluidAudio logs
(which contain model paths) are suppressed unless LOG_SENSITIVE_DATA=1.

VoiceMatcher uses the maximum sample cosine, threshold, margin, deterministic
score ordering and one-to-one assignment, preserving locked slots. Threshold 0.5
and margin 0.05 remain explicitly provisional until Plan 06.

Validation: 4 collector tests and 4 matcher tests passed. Model download and real
CAM++ inference are pending live verification; fake vectors do not establish model
quality.

Final automated verification: `swift test --parallel` passed all 138 tests
(19 new voice-related tests); `./local_build.sh Debug` succeeded. The profile store
suite was also rerun after the final erasure-order adjustment: 3/3 passed.

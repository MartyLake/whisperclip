# Phase 14 — Research

**Date:** 2026-10-15. Code state: `29735cd` (Phase 12 implemented, UAT recorded as pending).

## 1. Radnyk (`../stt-diarization`)

- Embedder: SpeechBrain `spkrec-ecapa-voxceleb` (PyTorch), 192-d (`server/server_audio.py:70-76`).
- `get_speaker_embedding` (`:132-194`): clean segments 1.2-5 s, fallback ≥ 0.6 s if < 3; 0.1 s margins; skip < 0.3 s;
  longest first; concatenated up to 15 s; one embedding per speaker per chunk.
- Matching (`:196-330`): `SIMILARITY_THRESHOLD = 0.63`; best = max cosine over a profile's samples; unmatched speakers
  become global speakers; speakers with < 5 s total are not offered for naming (`:352-364`).
- Profiles: `voice_profiles.json` `{profiles: [{name, embeddings: [[192 floats]]}]}`; 7 profiles, e.g. 9 samples for
  one person. Go tooling (`internal/voice/voice.go`): clean (merge same name, dedup ≥ 0.999, optional averaging),
  inspect (outliers / cross-speaker contamination), delete one sample.
- Naming: done after processing via the client; the server returns `unrecognized_profiles` with embeddings.

## 2. FluidAudio 0.17.7

- `CampPlusEmbedder` (`Sources/FluidAudio/Speaker/CampPlusEmbedder.swift`): `actor`, `load()` downloads
  `FluidInference/campplus-coreml` (public, not gated, 16.6 MB: preprocessor + CAM++ `.mlmodelc`),
  `embed(audio: [Float]) -> [Float]` for 16 kHz mono, output 192-d L2-normalised; `cosine` helper. Marked beta.
- `Nemotron3Diarizer` exposes no per-speaker identity vector (internal `chunkEmbeddings` feed its speaker cache).
- `DiarizerManager.extractSpeakerEmbedding` belongs to the removed pyannote path (11.4) — not used.
- SpeakerKit (argmax) also has centroids, but only from its batch pipeline (see IDEAS) — not used here.

## 3. App state

- System audio is not persisted (only temporary WAVs per ASR chunk and diagnostics). `SpeakerBufferManager`
  receives every system batch (`onAudioBatch`) and owns the 10 ms `SpeakerTimeline`; `SpeakerTimelineWindow.turns`
  gives single-speaker turns with times in capture seconds.
- Labels are created in `SpeakerReconciler` as `Speaker(displayName: "Speaker \(slot + 1)")` (`:88, :113`) and
  applied in `MeetingRecorder` (`:596`).
- `MeetingNote` is `Codable` JSON via `MeetingStorage.saveMeetings`; adding an optional field decodes old files.
  `MeetingStorage.update(_:)` writes a whole meeting.
- Settings: `SettingsView` `TabView` with General / Hotkey / Meetings / Prompts tabs.
- Phase 12: `ChatTranscriptView` / `TranscriptGroupBubble` headers — the place for the rename popover.

## 4. Risks

- CAM++ is beta; threshold unknown for our audio (call codecs, Ukrainian/English). Mitigation: Plan 06 calibration
  from logged scores; one-to-one assignment and margin reduce false matches.
- Nemotron slot quality bounds identity quality: a slot that mixes two people yields a mixed embedding. Collecting
  only single-speaker 1.2-5 s turns limits this.
- CPU: one CAM++ pass on ≤ 15 s every few seconds per slot is small next to ASR + Nemotron; run off the main actor.

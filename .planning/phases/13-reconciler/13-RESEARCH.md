# Phase 13 — Research

**Date:** 2026-10-14. Code state: `e93bfe2` (Phase 11.4 complete).

## 1. Current system-audio path (after 11.4)

- `MeetingRecorder.startRecording`: system batches → single ordered `AsyncStream` → `SpeakerBufferManager.onAudioBatch`
  when the model is loaded, else `accumulateSystemFallback` (fixed 5 s chunks, `systemFallbackChunkDuration`).
- With the model: `SpeakerBufferManager.emitTurns` cuts audio per closed turn (30 s cap, 0.5 s floor) →
  `buffers` → `transcribeClosedBuffer` → row created/finalized with "Speaker N". Text appears only after the
  turn closes and Nemotron has caught up (`fast32` ≈ 2.9 s).
- `onSpeechDetected` (Nemotron onset, ~3 s late) → `handleSystemSpeechDetected` creates the pending row and
  starts an 8 s ghost-cleanup timer.
- Without the model: `processAudioChunk(source: .system)` creates a pending row when the 5 s chunk closes,
  transcribes, finalizes as `.other`. `processAudioChunk` drops chunks < 2 s unless `isFinal`.

## 2. Word timings

- Parakeet: `ParakeetVoiceToTextModel.process/processStream` call `manager.transcribe(url, decoderState:)`,
  whose `ASRResult.tokenTimings: [TokenTiming]?` is ignored today. FluidAudio 0.17.7 ships
  `buildWordTimings(from:) -> [WordTiming]` (`ASR/Parakeet/AsrTypes.swift:183`) that groups SentencePiece
  pieces on `▁` / leading space. Times are relative to the start of the transcribed file.
- To verify in Plan 01: `tokenTimings` is non-nil for file transcription in 0.17.7, and times are in seconds
  from file start (not frames). If nil, fall back to `words = nil` (majority rule) and record it.
- WhisperKit: word timestamps exist (`DecodingOptions.wordTimestamps`) but are not used (D-02).

## 3. Timeline

- `SpeakerTimeline` (10 ms frames, `UInt8` slot+1) with `turns(from:to:)` (merge gap 0.2 s, min turn 0.2 s) and
  `dominantSpeaker(from:to:)`. Times are seconds since `sessionStartTime` (first system batch time).
- `timelineSnapshot()` copies the whole array (≈ 360 KB/hour). The Reconciler should query a window via a
  manager method (`turns(captureFrom:to:)`, `coveredThrough`), not copy the timeline per row.
- Nemotron streaming is causal: once frames are appended they never change, so a resolved row never needs
  re-resolution.

## 4. Live list and storage

- `MeetingSession.addPendingSegment` adds to `liveTranscript` only. `finalizeSegment` mutates the instance and
  calls `storage.addSegment` (first and only write for that row).
- `replaceSegment(id:with:)` removes from `liveTranscript` and calls `storage.addSegment` for the new rows, but
  `MeetingStorage` has no remove — if the old row was already finalized, the saved meeting keeps it. Hence D-03:
  split pending rows only, then finalize each part.
- `MeetingSegment.startTime/endTime` are `let`; a split creates new instances.

## 5. Risks

| Risk | Mitigation |
|------|------------|
| Chunk cut inside a word | Pause-based cuts (D-06); 8 s hard cap is rare in speech |
| Nemotron error / stall leaves rows pending | 10 s deadline → "Other" (D-09) |
| Overlap (two talking at once) | Dominant slot per word; < 0.6 s minorities ignored |
| Rows pending longer on `fast128` (~11 s) | Accepted; deadline must scale: `max(10 s, 2 × preset latency + 2 s)` |
| Stop ordering loses the tail | Capture stop → system stream drain → chunker flush → ASR drain → timeline finish → Reconciler final pass → queue drain |
| Ghost rows from VAD onset without speech | Keep existing ghost cleanup (empty text after 8 s → removed) |

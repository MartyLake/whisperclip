# Phase 13: Reconciler — Async Speaker Enrichment — Context

**Gathered:** 2026-10-14
**Status:** Ready for execution
**Depends on:** Phase 11.4 (Nemotron 3 timeline), Phase 11.2 (streaming ASR)

<domain>
## Phase Boundary

Today (after 11.4) system audio is transcribed only after Nemotron 3 closes a speaker turn, so remote speech
appears ~3 s + turn length after it is spoken. This phase inverts that: system audio is transcribed
immediately and shown under "Pending"; a Reconciler reads the Nemotron 3 timeline as it catches up and
assigns the speaker, splitting a row in two when it spans a speaker change.

In scope: timed transcription for system audio, Reconciler actor, pause-based system chunking, system
pending rows at speech onset, `SpeakerBufferManager` reduced to a timeline producer, stop ordering.

Out of scope: chat bubbles (Phase 12), voice profiles / naming (Phase 14), true token-by-token streaming of
system audio (system chunks stay whole-chunk transcriptions), microphone path (unchanged, always "Me").
</domain>

<decisions>
## Implementation Decisions

### Owner decisions (2026-10-14)

- **D-01 Text first, label later.** System audio is transcribed as soon as a phrase closes and shown with a
  "Pending" speaker; the Reconciler sets "Speaker N" when the timeline covers the row. Chosen over keeping
  diarizer-driven transcription with only an empty placeholder.
- **D-02 Split precision by backend.** Parakeet: rows are split at speaker changes word by word, using token
  timings (FluidAudio `ASRResult.tokenTimings` → `buildWordTimings`). WhisperKit: no split — the row gets the
  speaker with the most activity over its span. Word timestamps are not enabled for WhisperKit.

### Planner decisions

- **D-03 Resolve before storing.** A system row stays `isPending` (text visible, speaker "Pending") until the
  Reconciler resolves it; only then is it finalized and written to storage. Splits therefore happen before
  the first storage write — `MeetingStorage` has no remove API and `replaceSegment` after finalize would leave
  the old segment in the saved meeting (see RESEARCH §4).
- **D-04 `SpeakerBufferManager` becomes a timeline producer.** Audio buffering, turn cutting and the
  `buffers` stream are removed; it keeps feeding Nemotron 3, owns `SpeakerTimeline`, reports speech onsets,
  and answers timeline queries in capture time. `ClosedSpeakerBuffer` and `transcribeClosedBuffer` go away.
- **D-05 One system ASR path.** With or without the model, system audio goes through the same chunker and
  `processAudioChunk`. The only difference: with the model the row is handed to the Reconciler; without it
  it is finalized as "Other" immediately (current no-model behaviour).
- **D-06 Pause-based chunks.** Replace fixed 5 s system chunks with cuts at pauses: close a chunk after
  ≥ 400 ms below the system silence threshold, minimum 1 s of audio, hard cap 8 s. Fewer cuts mid-word,
  and text arrives shortly after each phrase instead of every 5 s.
- **D-07 System pending row at onset.** An energy VAD on system batches (reuse `VADStateMachine`) creates
  the "Pending" row when remote speech starts, independent of Nemotron. The Nemotron onset callback no longer
  creates rows; it only updates `activeSpeakers` and the waveform label.
- **D-08 Resolution rules** (all times in capture seconds):
  - wait until timeline coverage ≥ row end + 0.2 s (the timeline merge gap);
  - speakers with < 0.6 s inside the row are ignored as noise;
  - one remaining speaker → label the row;
  - several, with word timings → each word goes to the slot dominant over the word's span (fallback: the
    nearest turn); consecutive words of one speaker form one row; text is rebuilt from the words;
  - several, no word timings → the speaker with the most frames;
  - no speech frames in the span → nearest turn within 1.0 s, else "Other".
- **D-09 Deadline.** A row not resolvable within 10 s of its end (diarizer stalled or erroring) is finalized
  as "Other" and logged. At stop the timeline is finished first, then every remaining row is resolved once.
- **D-10 Same clock.** Timeline seconds are offset by `SpeakerBufferManager.sessionStartTime` (first system
  batch); chunk start times use the same system batch clock, so no conversion is needed beyond that offset.

### Carried decisions
- Mic stays "Me", no diarizer (2026-03-23). Slot i → "Speaker i+1" (11.4 D-04). No HF token (11.4 D-01).
- `.planning/**` never committed together with code.
</decisions>

<success_criteria>
From ROADMAP Phase 13, measured on `fast32` with Parakeet:
1. Every system row gets its speaker within ~2 diarizer windows (~6 s) of the audio being captured
2. A row spanning a speaker change is split at the change; no words are lost or duplicated
3. The Reconciler is a standalone actor, unit-tested without audio or models
4. The flat transcript updates correctly after a split or a label — no stale rows, no duplicates in the
   live list or in the saved meeting
</success_criteria>

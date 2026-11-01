# Phase 14: Voice Profiles — Named Speakers Across Meetings — Context

**Gathered:** 2026-10-15
**Status:** Ready for execution
**Depends on:** Phase 13 (Reconciler, Nemotron timeline), Phase 12 (bubble headers are the naming entry point)

<domain>
## Phase Boundary

Nemotron 3 separates speakers only within one session: slots become "Speaker 1/2/…" and mean nothing in the
next meeting. This phase adds speaker identity: a voice embedding per Nemotron slot, computed live from the
system audio; the user names a speaker once; the name is stored with voice samples and recognised
automatically in later meetings.

In scope: CAM++ embedder integration, per-slot voice sample collection, profile matching, live and saved-meeting
renaming, voice profile storage, Settings management (list / rename / merge / delete).

Out of scope: microphone speaker (always "Me"), importing Radnyk profiles (different model, see D-03), saving
meeting audio, cloud sync, re-diarizing old meetings, per-sample inspection tools (Radnyk `--inspect`).
</domain>

<decisions>
## Implementation Decisions

### Owner decisions (2026-10-15)

- **D-01 Name live and after.** Clicking a bubble header renames the speaker both in the live transcript during
  recording and in a saved meeting. During recording, later rows of that slot appear under the new name at once.
- **D-02 Always save the voice.** Every rename of a system speaker that has a voice embedding saves it: adds a
  sample to the profile with that name (trimmed, case-insensitive) or creates the profile. No toggle, no prompt.
  A speaker without an embedding (too little clean speech) is only renamed; the popover says why no voice was saved.

### Planner decisions

- **D-03 Embedder = FluidAudio CAM++.** `CampPlusEmbedder` (192-d, L2-normalised, CoreML; repo
  `FluidInference/campplus-coreml`, public, 16.6 MB, marked beta). Nemotron 3 does not expose identity
  embeddings. Radnyk's ECAPA vectors are also 192-d but live in a different space — they must never be compared
  with CAM++ vectors; no import.
- **D-04 Embeddings are computed live.** Meeting audio is not saved, so each slot's embedding is computed during
  recording and stored with the meeting (`MeetingNote.voices`). Naming after the meeting uses the stored embedding.
- **D-05 Sample collection (from Radnyk `get_speaker_embedding`).** Per slot, from Nemotron turns in the timeline:
  prefer single-speaker turns 1.2-5 s, trimmed by 0.1 s on each side; if fewer than 3 such turns, accept turns
  ≥ 0.6 s; skip pieces < 0.3 s. Longest pieces first, concatenated, capped at 15 s per slot.
- **D-06 When to embed.** At ≥ 4 s, ≥ 8 s and 15 s of collected clean speech per slot, and once more at stop.
  The latest embedding replaces the previous one. Speakers with < 5 s total speech in the meeting get no
  embedding saved (Radnyk rule) — the 4 s live embedding is used only for early matching.
- **D-07 Matching.** Score of a profile = max cosine over its samples. Accept the best profile if score ≥
  `Voice_Match_Threshold` and it beats the second best by ≥ `Voice_Match_Margin`. Assignment is one-to-one within a
  meeting: greedy by score, a profile already taken by another slot is skipped. Threshold and margin live in
  `Const.swift`; starting values 0.5 / 0.05 are placeholders — Radnyk's 0.63 is for ECAPA and does not transfer;
  the real values are set in the calibration step of Plan 06.
- **D-08 A match can upgrade, not flip.** Once a slot is matched to a profile it keeps that name for the meeting,
  unless the user renames it. Re-embedding only matches still-unnamed slots. Prevents names jumping mid-meeting.
- **D-09 Names over slots.** The Reconciler keeps emitting "Speaker N"; the recorder maps slot → display name
  (`speakerNames`) when it resolves a row. A new match or rename relabels existing rows of that slot in the live
  list and in storage. Identity of a slot in a meeting is `MeetingVoice.slot`, not the label string.
- **D-10 Same name twice = merge.** Renaming a speaker to a name already used by another speaker in the same
  meeting merges them (fixes a diarizer split); both embeddings are added as samples.
- **D-11 Profile storage.** `voice_profiles.json` in the app's Application Support folder, `0600`, complete file
  protection; up to 20 samples per profile (newest kept), near-duplicates (cosine ≥ 0.999) dropped (Radnyk
  `clean`). Deleting a profile removes its samples and also clears the embedding of every stored `MeetingVoice` linked to it; "delete all" clears embeddings from all stored meetings. Meeting text keeps its labels. Otherwise biometric copies would survive in meeting JSON.
- **D-12 Privacy.** Voice data never leaves the device; no network except the one-time model download. Logs: slot
  numbers, scores, counts, durations only; profile names only with `LOG_SENSITIVE_DATA=1`; never embeddings.
- **D-13 Off when unavailable.** If Nemotron or CAM++ is not available, recording works as today; the naming
  popover still renames, without saving voice (D-02 message).

### Carried decisions
- Mic stays "Me" (2026-03-23). Slot i → "Speaker i+1" (11.4 D-04). No HF token (11.4 D-01).
- Bubble grouping (Phase 12) groups by display speaker, so renaming merges/updates bubbles automatically.
- `.planning/**` never committed together with code.
</decisions>

<success_criteria>
From ROADMAP Phase 14:
1. Renaming "Speaker N" (live or saved) applies to all that speaker's rows and saves the voice (D-02)
2. In a later meeting the same person is labelled by name automatically; no false match between two enrolled
   people in a 3+ speaker test
3. Profiles can be listed, renamed, merged and deleted in Settings
4. No voice-profile data leaves the device
</success_criteria>

# Ideas

Unscheduled ideas. Nothing here is committed work: an entry moves to `ROADMAP.md` only after a decision to do it.

---

## D-1 — Parakeet models after FluidAudio upgrade

**Added:** 2026-10-13
**Status:** observed; no phase assigned

### Observation

- After upgrading to FluidAudio 0.17, previously downloaded Parakeet models are treated as not downloaded.
- FluidAudio 0.17 uses a different model folder (`parakeet-tdt-0.6b-v3/` instead of `parakeet-tdt-0.6b-v3-coreml/`) and a different v3 file set (`JointDecisionv3.mlmodelc`), so the existing local files do not satisfy the updated model checks.
- Workaround: download the Parakeet model again — confirmed working 2026-10-13.

### Defect before a fix

- The app allows recording to start before an STT model is ready, then surfaces only `[transcription failed]`.
- It is not yet confirmed whether Settings correctly shows the old Parakeet model as not downloaded.
- Confirmed 2026-10-13: re-downloading does NOT remove the obsolete files. `parakeet-tdt-0.6b-v3-coreml/` (461 MB) and `speaker-diarization-coreml/` (13 MB) stay orphaned in `~/Library/Application Support/FluidAudio/Models/`, and the app's "Delete" no longer reaches them.

### Checks

- Verify the model status shown in Settings after the upgrade.
- ~~Verify whether obsolete files are removed during or after re-download.~~ Done — they are not; add a one-time cleanup of pre-0.17 folders to the fix.
- Track the recording-without-ready-STT behavior as a defect; do not assign it to a phase yet.

---

## Hugging Face token in the UI

**Added:** 2026-10-13
**Status:** deferred — not needed today

- Planned for Phase 11.4 (TOKEN-01..03) on the assumption that `FluidInference/nemotron-3-diarization-coreml` was gated. Checked 2026-10-13: the repo is public and downloads anonymously, so the work was dropped from the phase.
- Becomes relevant if a model the app needs is gated, or if anonymous Hub downloads start being rate-limited for users.
- Shape if revived: token entered in Settings, stored in Keychain (never `UserDefaults`, never logged), passed to FluidAudio and WhisperKit through the `HF_TOKEN` environment variable (both read it from there); UI distinguishes "invalid token" from "no access to this repo".

---

## Review community fork work

**Added:** 2026-10-13
**Status:** undecided — owner is not yet sure any of it is needed
**Earliest sensible time:** after Phase 11.3 (the build must be green before porting anything)

### Background

- `suvaidkhan/whisperclip` (the GitHub parent of our fork) has been frozen since 2025-09-27; it is 0 commits ahead of our `dev-v2` and 108 behind.
- The real upstream was `cydanix/whisperclip` (all `Merge pull request #N from cydanix/...` commits come from it). It returned 404 on 2026-10-13 — private or deleted.
- The last public upstream release is 1.0.50 (2026-02-08, merge `cf764eb`), which we already contain. `dev-v2` = 1.0.50 + 58 own commits. There is no upstream left to fall behind.
- Of the 13 forks, only two carry their own work on top of 1.0.50. Neither touches diarization, streaming or the LLM stack.

### Candidates

Assessed from commit titles and file lists only — the code itself has not been read.

**`ColemanDunn/whisperclip`** — 5 commits, 2026-02-14..15, dictation UX:
- Focused-input guard before auto-paste (paste only when a text field has focus) — `GenericHelper.swift` (+513), with tests
- Clipboard-only mode
- Transcript retention policy and recording cleanup controls — `TranscriptionHistory.swift`, `SettingsStore.swift`, `Tests/TranscriptionHistoryTests.swift`
- Start/stop recording sounds — new `RecordingSoundManager.swift`
- Accessibility-permission flow changes — `SecurityChecker.swift`, `OnboardingView.swift`, `local_build.sh` / `local_run.sh`
- Recording overlay rework — `RecordingOverlayManager.swift` (+848). Likely to conflict: we changed this file in Phases 9-11

**`wwu-git/whisperclip`** — 3 commits, 2026-05-25, batch file transcription:
- Transcribe a folder of audio files: `AudioFileEnumerator`, `BatchTranscriptionCoordinator`, `BatchTranscriptionTypes`, `FileTranscriptionPipeline`, `TranscriptWriter`, each with tests
- Mostly new files; the only expected conflict is `FileTranscriptionView.swift` (+486 / -189)
- Also adds OpenSpec / Cursor tooling files that we would not take

### Open questions

- Is any of this wanted at all? Dictation polish and batch transcription are outside the v1.2 goal (live meeting transcription with speaker attribution).
- Licence and attribution for code taken from another fork.
- Port by cherry-pick or re-implement? Both forks branch from 1.0.50, 58+ commits behind us.

### How to look

```sh
gh api "repos/alexpalyan/whisperclip/compare/cf764eb...ColemanDunn:main"
gh api "repos/alexpalyan/whisperclip/compare/cf764eb...wwu-git:main"
```

---

## Post-meeting speaker refine pass via SpeakerKit

**Added:** 2026-10-15
**Status:** idea; no phase assigned
**Earliest sensible time:** after Phase 13 (needs the Reconciler to apply a corrected timeline)

### Idea

- After a meeting ends, run Argmax `SpeakerKit` (pyannote v3/v4 segmenter + embedder, VBx clustering) over the whole system-audio track and apply the result to the stored meeting through the Reconciler.
- Complements Nemotron 3, does not replace it: Nemotron stays the live/streaming diarizer; the refine pass only corrects the saved transcript.
- Expected win: global clustering over the full recording fixes live drift — one speaker split into two ids, or two similar voices merged.

### Why not a user-selectable alternative to Nemotron

- `SpeakerKit` in `argmax-oss-swift` 1.1.x is batch-only: `diarize(audioArray:)` takes the full audio. No streaming API; Sortformer is mentioned in `Diarizer.swift` comments but is not in the OSS package.
- Sliding-window re-runs to fake streaming would give unstable speaker ids between runs — the problem Phase 11.4 moved away from.
- It is the same pyannote family as the removed FluidAudio `DiarizerManager` (11.4-CONTEXT: "deleted, not kept as a fallback").
- A setting would double providers, model downloads, Reconciler branches and tests for a choice users cannot judge.

### Open questions

- Cost on a 1-hour meeting: time, peak memory (whole `[Float]` in RAM — ~230 MB at 16 kHz), model download size.
- Mapping SpeakerKit ids onto existing live ids (overlap-based matching vs. centroid distance) without breaking user-renamed speakers.
- Mic channel stays "Me" — refine runs on system audio only.
- Product is already in our dependency (`argmax-oss-swift` exposes `SpeakerKit`); only a target dependency line is needed.
- Related: `speakerCentroidEmbeddings` / `nearestSpeakerCentroid` as an embedder candidate for Phase 14 speaker identity (see 11.3-RESEARCH).

---

## Live notes and Q&A during a meeting

**Added:** 2026-10-15
**Status:** idea; no phase assigned
**Source:** owner saw it in Google AI Edge Foresight — not researched by us yet
**Earliest sensible time:** after Phase 13 (needs a stable live transcript with speakers); fits naturally next to Phase 12 Chat Bubble UI

### Idea

- **Quick notes mid-call:** the user types a short note ("ask Ivan about the budget", "deadline?") while the meeting is running. The local LLM (Gemma 4 E4B) expands it using the conversation so far — who said what, around which moment — into a full note anchored to the transcript timestamp.
- **Live Q&A:** ask a question about the meeting while it is still going ("what did they say about the release date?", "what did I miss in the last 5 minutes?").
- Fully on-device, same privacy story as the rest of the app.

### What already exists

- `MeetingAI.askQuestion(question:meeting:)` — Q&A, but only on a finished `MeetingNote`.
- `MeetingAI.truncateForLLM` keeps the *beginning* of the transcript (`prefix(20000)`). For a live meeting the *recent* part matters most — the context strategy has to change.

### Open questions

- Context budget for a long meeting: recent window + rolling summary of earlier parts? Reuse summary pieces as the meeting goes?
- Contention: Gemma running alongside live STT (Parakeet) and Nemotron diarization — latency, memory, thermals on base M-series. Queue/priority so LLM never starves transcription.
- Transcript is mutable (Reconciler can re-attribute speakers / fix text after the fact) — a note expanded at minute 10 may cite text that later changes. Re-expand, or freeze with the snapshot?
- Where notes live: `MeetingModels` field, shown inline in the bubble timeline, included in the final summary prompt.
- UI entry point: hotkey to drop a note without leaving the call app; a small input in the recording overlay?
- Logging: notes and questions are user content — same `LOG_SENSITIVE_DATA` rule as transcripts.

---

## D-2 — Meeting auto-detect misses Google Meet installed as a Chrome PWA

**Added:** 2026-10-15
**Status:** observed in code + live window list; no phase assigned (natural fit: the call-recording phase below)

- Owner runs Meet as a Chrome PWA (`~/Applications/Chrome Apps.localized/Google Meet.app`,
  bundle id `com.google.Chrome.app.kjgfgldnnfoeklkmfkjfagphfepbbdan`).
- Checked 2026-10-15 with `CGWindowListCopyWindowInfo` during a test call: the Meet windows are owned by the PWA
  process itself (owner name "Google Meet", that bundle id), not by `com.google.Chrome`.
- `MeetingDetector.checkBrowserForMeetings` only scans windows of browser bundle ids, and `MeetingSource.meet`
  lists `com.google.Chrome`, `com.apple.Safari`, `com.google.meet` — so a PWA call is most likely not detected.
- Fix shape: also scan `com.google.Chrome.app.*` (and Edge/Brave PWA prefixes if needed) and match the call title
  pattern below. Not verified that auto-detect actually fails for the owner — confirm first.

---

## Call recording: video of the call window + audio, saved to ~/Movies

**Added:** 2026-10-15
**Status:** owner wants it; plan as Phase 15 after Phase 14 closes

### Why

- Today the owner records calls with OBS and processes the video in Radnyk. Main pain: choosing the window to
  capture by hand every time.
- Saved audio also unlocks: post-meeting SpeakerKit refine (entry above), re-transcription with WhisperKit (better
  Ukrainian than Parakeet, owner 2026-10-15), better voice profiles from the whole meeting, play-from-bubble.

### Owner decisions (2026-10-15)

- Pick the call window automatically.
- When a Meet presentation is popped out into its own window, record **only the presentation**; switch back to the
  call window when it closes. Meeting audio continues without gaps.
- Save to `~/Movies` (app is not sandboxed; `~/Movies` is not TCC-protected — no new entitlement).
- Processing stays in WhisperClip (Radnyk processing is being moved into the app, 2026-10-15) — the file format is
  chosen for WhisperClip's own reprocessing, not for Radnyk.

### Facts from the live check (2026-10-15)

- Meet PWA call window title: `Google Meet - Meet: "abc-defg-hij" 🔊` — meeting code in quotes (`[a-z]{3}-[a-z]{4}-[a-z]{3}`),
  🔊 appears while audio plays. The home screen presumably has no code — not checked.
- Owner: PWA windows owned by the PWA bundle id; audio is rendered by the main Chrome process (OBS sees the Meet window
  separately but audio must be taken from "Google Chrome"). We capture whole-system audio, so this does not matter for us;
  per-app audio filtering would pull in every Chrome tab.
- The call window was reported `onscreen = false` (other Space / covered). To verify: ScreenCaptureKit
  `SCContentFilter(desktopIndependentWindow:)` delivers frames for a window on another Space; minimized windows give none.
- **Not yet checked:** what the popped-out presentation window looks like (title, owner). Owner could not pop one out
  while presenting their own screen — Meet does not render your own share. Try: join from a phone, present there, pop out in the
  PWA. Working assumption: a second large window of the same Meet PWA process during a call.

### Shape

- Window picker: per-source rules (Meet PWA / Meet in a browser tab / Zoom / Teams / Slack huddle — reuse
  `MeetingSource.windowTitleKeywords`), prefer keyword match then largest window; ambiguous → system
  `SCContentSharingPicker` (macOS 14), remember choice per app. Re-evaluate every few seconds and switch with
  `SCStream.updateContentFilter` (macOS 14).
- Writer: `AVAssetWriter` (`SCRecordingOutput` needs macOS 15; we support 14) — hardware HEVC, fixed output size with
  letterboxing (source window size changes on switch), 10-15 fps.
- Audio format (proposed, for our own reprocessing): **two separate mono tracks — mic and system — never mixed**.
  Matches the pipeline (mic = always Me; Nemotron/CAM++ run on system only) and lets each track be re-run alone.
  AAC 48 kHz ~96 kbps per track (~45 MB/h each): fine for ASR/embeddings after resampling to 16 kHz, good for playback.
  Lossless (ALAC 16 kHz, ~60 MB/h per track) is the alternative if AAC turns out to hurt re-transcription — decide in
  research with an A/B on one recording.
- Audio-only mode: the same two tracks in an `.m4a` when video is off (video and audio are separate switches).
- Time mapping: store the file's start in capture-clock seconds in the meeting, so a bubble can seek to its audio and
  reprocessing results map back onto existing segments.
- File: `~/Movies/WhisperClip <date time> — <source>.mov`; linked from the saved meeting; deleting the meeting asks
  whether to delete the video.
- Settings: on/off (default off), fps/quality, retention; visible recording indicator. Consent: recording others'
  video/voice may need all-party consent — say so in the setting.
- Logging: file paths only with `LOG_SENSITIVE_DATA=1`.

### Open questions

- Should the presentation switch also apply to Zoom/Teams screen-share windows, or Meet only at first?
- Later, not this phase: OCR of the active-speaker tile name (Vision) mapped onto the Nemotron timeline → automatic
  speaker names without renaming (extends Phase 14); slide text into Summary/Q&A context. Can run on live frames
  without saving video.

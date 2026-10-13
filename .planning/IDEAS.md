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

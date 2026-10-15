# Phase 15 — Research

**Date:** 2026-10-15. Code state: `3911444`.

## 1. Current locations (measured on the owner's account)

| Model | Path (under `~/Library/Application Support`) | Size |
|---|---|---|
| Gemma 4 E4B | `com.whisperclip/models/mlx-community/gemma-4-e4b-it-4bit` | 4.8 GB |
| WhisperKit large-v3 turbo | `com.whisperclip/models/argmaxinc/whisperkit-coreml/…` | 616 MB |
| Parakeet TDT v3 | `FluidAudio/Models/parakeet-tdt-0.6b-v3` | 461 MB |
| Parakeet EOU | `FluidAudio/Models/parakeet-eou-streaming` | 214 MB |
| Nemotron 3 | `FluidAudio/Models/nemotron-3-diarization` | 190 MB |
| (orphan, D-1) | `FluidAudio/Models/speaker-diarization` | 13 MB |
| CAM++ | `FluidAudio/Models/campplus-coreml` (not downloaded yet) | ~17 MB |

Per-user, not models: `com.whisperclip/tokenizers` (2.7 MB), `Diagnostics`, `recordings`, voice profiles, meetings.
Outside the app: Radnyk's `~/.cache/huggingface` (7.5 GB, includes another Gemma 4 E4B copy) and LM Studio
`~/.lmstudio/models` — not touched by this phase.

## 2. Code sites that resolve model paths

- `GenericHelper.getAppSupportDirectory()` → `~/Library/Application Support/<bundle id>`; used as `ModelDownloader`
  base in `ModelStorage.swift:12` (WhisperKit, MLX via `ModelStorage.getModelPath`), disk-space checks
  (`ModelStorage.swift:86`, `LocalParakeet.swift:108`) and — must stay per user — tokenizers
  (`LocalWhisperKit.swift:49`), diagnostics (`MeetingRecorder.swift:1455, 1504`), recordings (`AudioRecorder.swift:27`).
- `LocalParakeet.swift:10` `AsrModels.defaultCacheDirectory(for: .v3)`; `:14-26` streaming base
  `FluidAudio/Models`; `:125` `AsrModels.download(version:)` (no `to:`), `:148` `ModelHub.download(.parakeetEou160, to:)`.
- `ModelStorage.swift:286-339` `fluidAudioModelsDirectory`, Nemotron existence/delete; `:310` and
  `MeetingRecorder.swift:243` `Nemotron3Models.loadFromHuggingFace(config:)` without `cacheDirectory`.
- `SpeakerEmbedder.swift:23` `CampPlusEmbedder.load()` → `CampPlusModels.download()` uses a private
  `modelsRootDirectory()` = `~/Library/Application Support/FluidAudio/Models`; no directory parameter.
- FluidAudio APIs accepting a directory: `AsrModels.download(to:)`, `AsrModels.load(from:)`,
  `ModelHub.download(_:to:)`, `Nemotron3Models.loadFromHuggingFace(config:cacheDirectory:)` (base, then
  `repo.folderName`), `CampPlusModels.load(from:)`.

## 3. Permissions experiment (APFS, 2026-10-15)

- `/Users/Shared` is `root:wheel drwxrwxrwt` (sticky): any user can create a top-level folder there; folders the
  app creates get `755` (umask 022) → other users read-only.
- `chmod +a "group:staff allow …,file_inherit,directory_inherit"` on a root: new subfolders and files created inside
  got the inherited ACL (`read,write,execute,delete,append,…` for files). Rename within the tree keeps it.
- A file created outside and `mv`-ed in kept no ACL → must be repaired (D-04).
- Owner account is in `staff` and `admin`; standard users are in `staff`.
- Swift: use Darwin `acl_init` / `acl_create_entry` / `acl_set_file` (or `acl_from_text`) — no subprocess.

## 4. Risks

- A downloader that sets explicit POSIX modes or replaces whole folders could drop the ACL — the repair pass covers it.
- Root created by an older build without ACL: only its owner can add the ACL; other users fall back to a per-user
  location with a logged warning until the owner launches the app once.
- Fast user switching while both users download the same model — lock (D-05).

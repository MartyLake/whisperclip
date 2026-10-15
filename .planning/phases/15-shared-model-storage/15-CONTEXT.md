# Phase 15: Shared Model Storage — Context

**Gathered:** 2026-10-15
**Status:** Ready for execution
**Depends on:** none (touches model loading only; can run while Phase 14 calibration/UAT is open)

<domain>
## Phase Boundary

Every macOS user downloads all models into their own `~/Library/Application Support` (measured 2026-10-15:
≈ 6.3 GB per user — Gemma 4 E4B 4.8 GB, WhisperKit large-v3 turbo 616 MB, Parakeet TDT v3 461 MB, Parakeet EOU
214 MB, Nemotron 3 190 MB, CAM++ ~17 MB). The owner works under several macOS accounts; avoiding per-user
downloads is the reason Radnyk exists. This phase moves model files to one machine-wide folder that every user
can read, update and delete without admin rights.

In scope: shared root folder with inherited permissions, all model download/load paths pointed at it,
permission repair after downloads, a cross-user download lock, migration of models already downloaded by the
current user, Settings text.

Out of scope: per-user data (meetings, voice profiles, settings, diagnostics, recordings, WhisperKit tokenizer
cache) — stays per user. Reusing model copies from LM Studio / Hugging Face cache (see IDEAS). Custom location
picker. Orphaned pre-0.17 FluidAudio folders (D-1).
</domain>

<decisions>
## Implementation Decisions

### Owner decisions (2026-10-15)

- **D-01 One shared folder for models.** Choice between `/Users/Shared/WhisperClip/Models` and
  `/Library/Application Support/WhisperClip/Models`, resolved by D-02.

### Planner decisions

- **D-02 Location: `/Users/Shared/WhisperClip/Models`.** Any user can create it — no admin prompt, whoever launches
  first sets it up. `/Library/Application Support` is `root:admin 755`: creating it needs an admin authorization,
  a standard (non-admin) user could not be first, and it would still need the same permission fix (D-03).
- **D-03 Inherited ACL for group `staff`.** Plain POSIX permissions do not work for sharing: with umask 022 every
  folder/file a downloader creates is `755/644` owned by that user, so another user cannot add, update or delete
  inside it. FluidAudio also writes at load time (Nemotron `discardStaleCache`, WhisperKit Hub metadata cleanup), so
  read-only sharing is not enough. Fix: on creation, put an inheritable ACL on the root —
  `group:staff allow list,add_file,search,add_subdirectory,delete_child,readattr,writeattr,readextattr,writeextattr,readsecurity,read,write,append,execute,delete,file_inherit,directory_inherit`.
  All standard macOS users are in `staff`. Verified 2026-10-15 on APFS: folders and files created inside inherit it.
- **D-04 Repair after every download and move.** Also verified: a file *moved* into the tree from elsewhere keeps its
  own (empty) ACL and is not writable by others. Downloaders write to a temp location and move into place, and
  migration moves folders. So after each download / migration the app applies the ACL recursively to the new
  subtree (items owned by the current user only; others' items were repaired by their owner).
- **D-05 Cross-user download lock.** Two users can be logged in at once (fast user switching). Downloads and
  deletions of a model take an exclusive `flock` on `<root>/.locks/<model>.lock` (wait with timeout and progress
  "another user is downloading"); loads take no lock.
- **D-06 Layout mirrors today's.** `<root>/models/<repo-id>/…` for our `ModelDownloader` (WhisperKit, MLX LLMs) and
  `<root>/FluidAudio/…` for FluidAudio repos (Parakeet, Parakeet EOU, Nemotron 3, CAM++), so existing existence
  checks keep working with only a base-path change. FluidAudio APIs used with an explicit directory:
  `AsrModels.download(to:)` / `load(from:)`, `ModelHub.download(_:to:)`, `Nemotron3Models.loadFromHuggingFace(config:cacheDirectory:)`,
  CAM++ via `ModelHub.download(.campPlus, to:)` + `CampPlusModels.load(from:)` (its `download()` has no directory).
- **D-07 Migration by move.** On launch, for each known model in the current user's old folders: shared copy
  missing → move (same volume, instant) + repair; shared copy present and complete → delete the local duplicate;
  incomplete either side → leave as is and let the normal download fill the shared copy. Logs sizes only.
- **D-08 Delete means for everyone.** Deleting a model in Settings removes it for all users; the UI says so.
  Settings shows the shared location with "Show in Finder".
- **D-09 Not in backups.** Mark the shared root `isExcludedFromBackup` (models are re-downloadable, 6+ GB).
- **D-10 Trust note.** Any local user can modify shared model files. Acceptable for a personal/family Mac; recorded
  as a known limitation, not mitigated.
- **D-11 Per-user caches are fine.** CoreML keeps its compiled/ANE-specialised caches per user automatically; the
  first load per user is slower once. MLX reads weights via mmap, read-only.

### Carried decisions
- arm64 only; app is not sandboxed (if it ever is, `/Users/Shared` needs an entitlement exception).
- Never log model paths unless `LOG_SENSITIVE_DATA=1`.
- `.planning/**` never committed together with code.
</decisions>

<success_criteria>
1. All models live under `/Users/Shared/WhisperClip/Models`; no model files remain in per-user folders after migration
2. A second macOS user launches the app and uses every model (STT, Nemotron, CAM++, Gemma) with no download
3. Any user can update or delete a model downloaded by another user, without admin rights
4. Models already downloaded are moved, not downloaded again; per-user data stays per user
</success_criteria>

# 15-02 — Shared model paths

All app-managed Hugging Face models resolve under `<shared-root>/models`; FluidAudio Parakeet, EOU, Nemotron 3, and CAM++ resolve under `<shared-root>/FluidAudio/Models`. Downloads, replacements, and deletions use process locks and repair ACLs after successful downloads. When shared storage is unavailable, paths and locks fall back to the current user's Application Support directories.

| Data | Location |
|---|---|
| WhisperKit and MLX models | Shared `models/` |
| Parakeet, EOU, Nemotron 3, CAM++ | Shared `FluidAudio/Models/` |
| WhisperKit tokenizer cache | Per-user `tokenizers/models/` |
| Meetings, profiles, settings, diagnostics, recordings | Per-user |

`ModelPathsTests` (3 tests) checks injected shared roots, non-owner fallback resolution, model paths, and the per-user tokenizer location. Settings reports the shared download wait state.

## Verification

- `swift test --parallel`: 150 tests passed (arm64, 2026-10-15).
- `swift build`: succeeded. Existing Swift concurrency and fixture warnings remain.

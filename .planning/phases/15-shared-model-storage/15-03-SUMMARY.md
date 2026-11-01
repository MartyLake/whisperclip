# 15-03 — Migration and Settings

Added a launch migration barrier before model loads. It moves known WhisperKit, MLX, Parakeet, EOU, Nemotron 3, and CAM++ caches when the shared copy is absent; removes a local duplicate only when the shared model check reports complete; and leaves incomplete shared copies alone. Moved items have their shared ACL repaired. Migration logs actions and sizes, and only includes filesystem error details when sensitive logging is enabled.

Settings shows the current model location, opens it in Finder, explains that deletion affects all Mac users, and asks for confirmation before deleting LLM or Nemotron models. Existing onboarding model-presence checks now inspect the shared paths.

`ModelMigrationTests` (4 tests) covers move and permission repair, complete duplicate cleanup, incomplete-copy preservation, and idempotence.

## Verification

- `swift test --filter ModelMigrationTests`: 4 tests passed (arm64, 2026-10-15).
- `swift test --parallel`: 150 tests passed (arm64, 2026-10-15).
- `swift build`: succeeded.
- Two-account macOS verification remains in Plan 04.

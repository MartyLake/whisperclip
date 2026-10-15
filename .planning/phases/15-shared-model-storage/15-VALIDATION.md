---
phase: 15
slug: shared-model-storage
status: in_progress
created: 2026-10-15
---

# Phase 15 — Validation Strategy

> ACLs, locking, path resolution and migration are tested in temp folders as one user. Access by a second macOS
> account is proven only by Plan 04.

| Property | Value |
|----------|-------|
| **Framework** | XCTest |
| **Quick run** | `swift test --filter SharedModelStoreTests` / `ModelPathsTests` / `ModelMigrationTests` |
| **Full suite** | `swift test --parallel` |
| **App build** | `./local_build.sh Debug` |

## Per-Task Verification Map

| Task | Wave | Requirement | Type | Command | Status |
|------|------|-------------|------|---------|--------|
| 01 T1 | 1 | MODELS-01, MODELS-02 | Unit (TDD) | `swift test --filter SharedModelStoreTests` | ✅ 5 passed |
| 02 T1 | 2 | MODELS-01, MODELS-02 | Unit + build | `swift test --parallel`; `swift build` | ✅ 150 passed; build succeeded |
| 03 T1 | 3 | MODELS-03 | Unit (TDD) | `swift test --filter ModelMigrationTests` | ✅ 4 passed |
| 03 T2 | 3 | MODELS-04 | Build | `swift build` | ✅ succeeded |
| 04 T1 | 4 | MODELS-01..04 | Manual, two accounts | see 15-04-PLAN | ⬜ |

## Security / privacy

- Only model files are shared; meetings, transcripts, voice profiles, settings stay per user.
- Shared model files are writable by every local user (D-10) — known limitation.
- Model paths logged only with `LOG_SENSITIVE_DATA=1`. No network in tests.

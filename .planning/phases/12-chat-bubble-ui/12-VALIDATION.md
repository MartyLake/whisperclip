---
phase: 12
slug: chat-bubble-ui
status: awaiting-uat
created: 2026-10-15
---

# Phase 12 — Validation Strategy

> Grouping and colour mapping are pure and tested with constructed segments. Layout, alignment, animation and
> scrolling are covered only by Plan 03.

| Property | Value |
|----------|-------|
| **Framework** | XCTest |
| **Quick run** | `swift test --filter TranscriptGroupingTests` / `SharedViewsTests` |
| **Full suite** | `swift test --parallel` |
| **App build** | `./local_build.sh Debug` |

## Per-Task Verification Map

| Task | Wave | Requirement | Type | Command | Status |
|------|------|-------------|------|---------|--------|
| 01 T1 | 1 | CHAT-01..04 | Unit (TDD) | `swift test --filter TranscriptGroupingTests` | PASS |
| 01 T2 | 1 | CHAT-02 | Unit (TDD) | `swift test --filter SharedViewsTests` | PASS |
| 02 T1-T2 | 2 | CHAT-01..04 | Build + suite | `swift test --parallel`; `./local_build.sh Debug` | PASS |
| 03 T1 | 3 | CHAT-01..04 | Manual | see 12-03-PLAN | ⬜ |

## Security / privacy

- UI-only phase: no new logging; transcript text never logged.
- No network in tests; no model downloads.

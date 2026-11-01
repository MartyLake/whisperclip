# Phase 15 — Shared model storage UAT

Manual two-account verification is pending. Run Plan 04 with the same signed app build in `/Applications`, then record observations and mark each step PASS or FAIL.

| Step | Result | Notes |
|---|---|---|
| User A models migrate to shared storage without re-download; shared ACL is present | ⬜ | |
| User A uses WhisperKit, Parakeet, Nemotron 3, CAM++, and Gemma | ⬜ | |
| Standard User B uses the same models without downloading | ⬜ | |
| User B deletes and re-downloads a model; User A can still use it | ⬜ | |
| Concurrent same-model download waits and resumes without corruption | ⬜ | |
| Meetings, profiles, and settings remain per-user | ⬜ | |
| `tmutil isexcluded /Users/Shared/WhisperClip/Models` reports exclusion | ⬜ | |

Unit tests and a local build do not prove cross-account ACL, fast-user-switching, or backup behavior.

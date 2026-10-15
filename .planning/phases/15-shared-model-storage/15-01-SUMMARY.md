# 15-01 — Shared model storage primitives

Implemented `SharedModelStore` with an injectable root, shared directory layout, backup exclusion, recursive ACL repair, and async/sync `flock` locks. ACLs are built with Darwin ACL calls and the Directory Services group-to-UUID API; the root grants `staff` inherited access and repaired items receive item-appropriate rights. Model locations resolve to the shared root or per-user fallback.

`SharedModelStoreTests` (5 tests) covers layout, ACL inheritance, idempotence, moved-file repair, lock ordering, and timeout.

## Verification

- `swift test --filter SharedModelStoreTests`: 5 tests passed (arm64, 2026-10-15).

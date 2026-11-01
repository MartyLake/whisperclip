---
phase: 14-voice-profiles
plan: 05
status: implemented
completed: 2026-10-15
---

Code commit: `2afbf8e` (code and tests only).

# Plan 14-05 execution summary

Added the Voices settings tab after Meetings. Profiles show their name, sample
count and update date. Selection enables rename and delete; selecting two profiles
enables Merge into, explicitly choosing the surviving name. Delete and delete-all
require confirmation. The empty state explains enrollment through speaker naming,
and the footer explains local biometric storage and erasure behavior.

MeetingStorage.clearVoiceEmbeddings(profileID:) and clearAllVoiceEmbeddings()
remove stored embeddings without changing transcript names. Profile merges relink
stored profile IDs. Live snapshots resolve merge aliases and honor erasure to
prevent a later recorder update from restoring deleted biometric copies.

Validation: profile store and privacy-erasure tests passed; Debug build succeeded.
Settings interaction and first-run offline model fallback are pending manual UAT.

Final automated verification: `swift test --parallel` passed all 138 tests
(19 new voice-related tests); `./local_build.sh Debug` succeeded. The profile store
suite was also rerun after the final erasure-order adjustment: 3/3 passed.

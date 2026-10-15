---
phase: 14-voice-profiles
plan: 04
status: implemented
completed: 2026-10-15
---

Code commit: `2afbf8e` (code and tests only).

# Plan 14-04 execution summary

Added a shared async rename entry point on MeetingSession for live and saved
meetings. It relabels all affected rows, uses canonical case-insensitive profile
names, saves available embeddings automatically, locks manual live assignments and
merges same-name speakers. Empty names and renaming Me are rejected. Without an
embedding, text is renamed and the popover explains that no voice was saved.

Non-Me resolved bubble headers now open SpeakerRenamePopover, with a hover pencil,
text field, profile suggestions, Return/Save, Cancel and an inline result. Both
MeetingNotesView's live transcript and MeetingDetailView use this handler. Speaker
statistics already derive their labels from the updated meeting segments.

Validation: SpeakerRenameTests cover saved rename, merge, automatic enrollment,
case-insensitive names, text-only fallback, protected Me, empty names, live relabel,
old JSON, voice round-trip and erasure during a live meeting. Automated tests and
Debug build passed. Visual interaction and live microphone/system audio UAT remain
pending Plan 06.

Final automated verification: `swift test --parallel` passed all 138 tests
(19 new voice-related tests); `./local_build.sh Debug` succeeded. The profile store
suite was also rerun after the final erasure-order adjustment: 3/3 passed.

---
phase: 14-voice-profiles
plan: 02
status: implemented
completed: 2026-10-15
---

Code commit: `2afbf8e` (code and tests only).

# Plan 14-02 execution summary

Implemented VoiceProfileStore (MainActor ObservableObject) with injectable file
URL and meeting store. Default file: ~/Library/Application Support/WhisperClip/
voice_profiles.json. Atomic writes use complete file protection and POSIX 0600;
the containing directory is created with 0700. Existing files are protected on
load; corrupt input is preserved as a protected .bak and starts an empty store.
Successful erasure also removes the backup.

APIs: profile(named:), addSample(_:toProfileNamed:), rename(_:to:), merge(_:into:),
delete(_:), deleteAll(), vectors. Mutations throw persistence failures to the UI.
Names are trimmed and compared case-insensitively. Samples must be finite 192-d
nonzero CAM++ vectors, near-duplicates are discarded at cosine >= 0.999, and each
profile retains at most 20 samples.

MeetingVoice stores slot, label, optional embedding, speech duration and profile
ID. MeetingNote explicitly decodes missing voices as an empty array. Meetings
continue to use the existing MeetingStorage UserDefaults JSON persistence (the
research's reference to a meetings Application Support folder did not match the
actual code).

Validation: 3 store tests cover round-trip, 0600, dedup, cap, merging, corrupt
input, invalid samples and erasure of linked meeting copies. Meeting compatibility
and voice round-trip are covered in SpeakerRenameTests.

Final automated verification: `swift test --parallel` passed all 138 tests
(19 new voice-related tests); `./local_build.sh Debug` succeeded. The profile store
suite was also rerun after the final erasure-order adjustment: 3/3 passed.

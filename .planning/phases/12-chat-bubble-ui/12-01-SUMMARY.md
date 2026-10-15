# Plan 12-01 — Complete

Implemented `TranscriptGrouping.groups(from:maxGap:)` (default 30 s) and
`TranscriptGroup` with first-segment identity, speaker, segments, time bounds,
Me/pending flags and typing-tail state. Input order is preserved.

Rules in order: open first group; break on gap > maxGap; append pending to
non-Me; append matching key; pending-only group adopts a non-Me key;
otherwise open a new group. Mic pending rows retain the Me display key.

Speaker N maps to 2 + (N - 1) % 7; custom labels use UTF-8 FNV-1a 64-bit.
Nine grouping tests and six SharedViews tests pass in the full 119-test suite.
Tests and implementation were added together; a strict red/green TDD cycle
was not recorded. Initial sandbox run failed on compiler cache access;
the authorized run passed.

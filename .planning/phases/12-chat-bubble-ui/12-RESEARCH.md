# Phase 12 — Research

**Date:** 2026-10-15. Code state: `17b1862` (Phase 13 closed).

## 1. Current transcript views

- Live: `MeetingNotesView` (`Sources/MeetingNotesView.swift:136-165`) — `ScrollViewReader` + `LazyVStack`,
  `ForEach(session.liveTranscript)` → `LiveSegmentRow` (`:485`). Auto-scroll on `liveTranscript.count` only.
  `LiveSegmentRow` uses `segment.speaker`, not `displaySpeaker` (minor inconsistency, disappears with the rewrite).
- Saved: `MeetingDetailView.transcriptContent` (`Sources/MeetingDetailView.swift:430-450`) — speaker stats card,
  then `VStack` + `ForEach(currentMeeting.segments)` → `TranscriptSegmentRow` (`:668`, time / name / text,
  `.textSelection(.enabled)`).
- `TypingIndicator` (`MeetingDetailView.swift:725`) is used by both rows; keep it, move to the new file.
- No other users of the two rows (grep).

## 2. Data and observation

- `MeetingSegment` is `@Observable final class` (`MeetingModels.swift:111`): `speaker`, `text`, `isPending`
  change in place. `MeetingSession.liveTranscript` is `@Published [MeetingSegment]`, kept sorted by
  `startTime` (`MeetingSession.swift:273, 287, 321, 330`).
- Resolve paths (Phase 13): `finalizeSegment` mutates the instance (label path); `resolvePendingSegment`
  replaces one row by its parts at the same index (split path). Both wrap changes in
  `withAnimation(.easeInOut(duration: 0.2))`.
- Grouping computed inside `body` reads `speaker` / `isPending` / `text` of each segment, so Observation tracks
  them and the view recomputes on a label change even when the array is unchanged.
- `displaySpeaker`: pending + not Me → `.pending`; mic rows stay `.me`.
- Saved meetings (`MeetingNote.segments`) contain only finalized rows (13 D-03), so the pending rules only matter
  live.

## 3. Colours

- `speakerPaletteColor` (`SharedViews.swift:8`) indexes a 9-colour palette by `Speaker.colorIndex`.
- `colorIndex` for `.labeled(l)` = `2 + abs(l.hashValue) % 7` (`MeetingModels.swift:~104`). `String.hashValue`
  is seeded per process → colours differ across launches, and "Speaker 1"/"Speaker 2" may collide.
  `SharedViewsTests` only checks the range, so it does not catch this.

## 4. Risks

- Large meetings: grouping is O(n) per body evaluation; ~1-2k rows per hour → negligible. The saved view uses a
  plain `VStack`; with groups the view count drops, so no change needed.
- Merge/split animation: removing a header when two groups merge is a small vertical shift. Acceptable; the
  common case (D-05) is a bubble that only grows.

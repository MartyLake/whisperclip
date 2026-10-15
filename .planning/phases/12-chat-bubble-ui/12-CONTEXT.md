# Phase 12: Chat Bubble UI — Context

**Gathered:** 2026-10-15
**Status:** Ready for execution
**Depends on:** Phase 13 (Reconciler, closed `17b1862`), Phase 10 (mutable `MeetingSegment`)

<domain>
## Phase Boundary

Both transcript screens show a flat list today: one row per ASR chunk, each with its own name, time and
icon. After Phase 13 a remote speaker's turn arrives as several phrase-sized rows (pause cuts ≥ 400 ms), so
one turn reads as many rows. This phase groups consecutive rows of one speaker into one chat bubble.

In scope: a pure grouping model, one shared bubble transcript view, wiring it into the live transcript
(`MeetingNotesView`) and the saved meeting (`MeetingDetailView`), stable per-speaker colours, removal of
`LiveSegmentRow` and `TranscriptSegmentRow`.

Out of scope: renaming speakers / voice profiles (Phase 14), changes to the Reconciler or ASR, speaker
stats card (kept as is), summary / Q&A tabs, export formats.
</domain>

<decisions>
## Implementation Decisions

### Owner decisions (2026-10-15)

- **D-01 Both screens.** Bubbles replace the flat list in the live transcript during recording and in the
  saved meeting. One shared view, so both look the same. (ROADMAP named only `MeetingDetailView`; the owner's
  feedback came from the live view.)
- **D-02 One bubble per turn.** Consecutive rows of one speaker merge into a single bubble with continuous
  text — not an iMessage stack of per-row bubbles. Text still being resolved is appended at the end in a
  muted colour.

### Planner decisions

- **D-03 Grouping is a pure function.** `TranscriptGrouping.groups(from: [MeetingSegment]) -> [TranscriptGroup]`,
  recomputed from the sorted list on every update; no grouping state is stored. Unit-tested without UI.
- **D-04 Group key = display speaker.** `.me`, each `.labeled(name)`, `.other` and `.unknown` are distinct keys.
  A mic row is `.me` even while pending (`displaySpeaker` already does this).
- **D-05 Pending system rows join the previous turn.** A row whose display speaker is `.pending` is appended
  to the immediately preceding group if that group is not Me and within the gap (D-06); otherwise it opens a
  pending group (header "…", neutral colour, dashed border). Reason: most phrases continue the current
  speaker, so the bubble only grows and nothing jumps when the label arrives. If the Reconciler resolves the
  row to a different speaker, the next recompute splits it into a new group after the current one. Accepted
  cost: for a few seconds a pending phrase is shown (muted) inside the previous speaker's bubble.
- **D-06 Gap break.** A new group starts when the gap from the previous row's end to this row's start is
  > 30 s, even for the same speaker, so a long monologue still gets time anchors.
- **D-07 Group identity.** `TranscriptGroup.id` = id of its first segment. Appending rows keeps the id, so
  `ForEach` updates the bubble in place; only real merges/splits insert or remove views.
- **D-08 Layout.** Me: right-aligned, blue tint; others: left-aligned, speaker colour tint. Header (speaker name,
  "Me" included) once above the bubble; group start time (`mm:ss`) once below it. Bubble width is limited by a
  minimum spacer (~48 pt) on the opposite side — no `GeometryReader` per row. Alignment never changes on
  resolve: Me rows are never `.pending`, and every non-Me key is left-aligned.
- **D-09 Single text run.** Bubble text is one `Text` built from an `AttributedString`: resolved rows in the
  primary colour, pending rows in `.secondary`, joined with a space. Saved meeting: `.textSelection(.enabled)`
  on the whole bubble. A trailing pending row with empty text shows `TypingIndicator` under the text (or alone).
- **D-10 Stable colours.** `Speaker.colorIndex` for `.labeled` currently uses `String.hashValue`, which Swift
  randomises per process: "Speaker 1" can change colour between launches. Replace with: parse `Speaker N` →
  `2 + (N - 1) % 7`; any other label → a deterministic hash (FNV-1a over UTF-8) into 2…8.
- **D-11 Live auto-scroll.** Scroll to a bottom anchor when the row count changes and when the last row's text
  changes (a growing bubble does not change the count).

### Carried decisions
- Mic stays "Me" (2026-03-23). Slot i → "Speaker i+1" (11.4 D-04). WhisperKit rows are not split (13 D-02),
  so grouping must not depend on word timings.
- `.planning/**` never committed together with code.
</decisions>

<success_criteria>
From ROADMAP Phase 12, applied to both screens (D-01):
1. Consecutive rows of one speaker form one bubble — no repeated name or avatar inside a turn
2. Each bubble shows the speaker name (or "Me") once on top and one timestamp at the bottom
3. Me right-aligned, all other speakers left-aligned
4. A "Pending" phrase resolves in place: no layout jump, no full-list reload
5. The flat-list rows are fully replaced; no regression in MeetingDetailView navigation, storage, copy/export
</success_criteria>

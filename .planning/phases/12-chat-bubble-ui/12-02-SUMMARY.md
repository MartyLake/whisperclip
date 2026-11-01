# Plan 12-02 — Complete

`ChatTranscriptView` computes groups inside body and renders shared
`TranscriptGroupBubble` views in live and saved transcripts. Header and footer
appear once per turn; Me aligns right, other groups left. One attributed text
run supports muted pending text and saved-meeting selection. Pending-only
bubbles have a neutral dashed border. TypingIndicator moved unchanged.

Live uses a plain VStack to avoid lazy height estimation while bubbles grow.
A bottom anchor scrolls on count and last-text changes. Old row types removed.
Stats, summary, Q&A, storage and export code were left intact.

Validation: `swift test --parallel` passed (119 tests); `./local_build.sh Debug`
passed. SwiftPM compilation also verified the shared view. Explicit attribute
subscript avoids a new SwiftUI non-Sendable key-path warning. Existing unrelated
project/dependency warnings remain. `git diff --check` passed.

Visual appearance, resolve animation, text selection and long-meeting scrolling
remain pending real-audio UAT in Plan 03.

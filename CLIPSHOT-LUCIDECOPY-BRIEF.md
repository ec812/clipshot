# UI: copy glyph in card footer → lucide-style copy icon

Project root: /Users/ernest/projects/clipboard (this IS the working directory)
Branch: feature/horizontal-scroll (stay on it).

## Request

The footer's copy button currently uses the SF Symbol `doc.on.doc`
(CardChrome.swift:205). The user wants a glyph like lucide's React
`copy` icon instead — the stroke-style icon of two overlapping rounded
squares.

Lucide `copy` paths (24x24 viewBox, stroke width 2, stroke-linecap round,
stroke-linejoin round, fill none):

```
<rect width="14" height="14" x="8" y="8" rx="2" ry="2"/>
<path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>
```

Meaning visually: a full rounded square at top-left (the "source"
document, drawn as an L-shaped outline that closes into a square) and a
second rounded square overlapping it at bottom-right.

## Implementation constraints

- Native SwiftUI app — do NOT add JS/font/SVG-file dependencies. Draw it
  as a SwiftUI Shape/View (Path + addRoundedRect + strokes), scaled from
  the 24-unit lucide grid to the button's glyph size, strokeWidth scaled
  proportionally (2/24 of the drawn size), using `.stroke` with the same
  foreground color the other footer glyphs get (currentColor semantics —
  inherit from the label/foregroundStyle, `.medium`-ish visual weight to
  match neighbors `pin` and `ellipsis`).
- Scope: ONLY the copy button's glyph (CardChrome.swift FooterIconButton
  call at line 205). The paste glyph (`doc.on.clipboard`), pin and
  ellipsis stay as-is unless a tiny shared helper makes the copy icon
  clean — do not restyle other buttons.
- Must scale correctly for both compact and non-compact (footerGlyphSize
  differs) — use the size the FooterIconButton already passes in.
- No new files unless a small dedicated view file is genuinely cleaner;
  if you add one, register it in the pbxproj.

## Verification gate (required)

1. Build, filtered to touched area (must print nothing):
   `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug build 2>&1 | grep -E "(warning|error)" | grep -i cardchrome`
2. Full suite:
   `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug test 2>&1 | tail -5`
   → `** TEST SUCCEEDED **`, 152 tests (count must not drop), 0 failures.

## Handoff

Commit on feature/horizontal-scroll, message states what changed.
Report: files changed, build/test results. Flag that final visual
judgment is the user's — I'll have the user eyeball it.

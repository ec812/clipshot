# UI: paste + pin footer glyphs → lucide SVGs (exact user-provided paths)

Project root: /Users/ernest/projects/clipboard (this IS the working directory)
Branch: feature/horizontal-scroll (stay on it).

## Request

Follow-up to the lucide copy glyph (commit 681e330). The user supplied
data-URI SVGs for the remaining two footer glyphs. Data URIs can't load in
a native app — decode once, draw as SwiftUI Shapes from these EXACT
paths (already decoded from base64; verbatim):

### Paste — lucide `clipboard-paste`, 24×24, fill none, stroke
currentColor, stroke-width 2, round caps/joins:

```
<path d="M11 14h10"/>
<path d="M16 4h2a2 2 0 0 1 2 2v1.344"/>
<path d="m17 18 4-4-4-4"/>
<path d="M8 4H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 1.793-1.113"/>
<rect x="8" y="2" width="8" height="4" rx="1"/>
```

### Pin — lucide `pin`, same stroke attributes:

```
<path d="M12 17v5"/>
<path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"/>
```

## Scope

- CardChrome.swift only (match how 681e330 did copy): extend the existing
  FooterGlyph enum (or equivalent) with `.lucideClipboardPaste` and
  `.lucidePin`; the paste button (currently `doc.on.clipboard`) and pin
  button (currently `pin` / `pin.fill`) switch to the lucide glyphs.
- Keep the same scaling math as the copy shape (24-unit grid, strokeWidth
  = glyphSize * 2 / 24, round caps/joins, stroke inherits foreground
  color) — all three must look like one family.
- The copy glyph from 681e330 stays as-is unless its paths differ from
  the user's copy SVG above (compare: rect 14×14 @8,8 rx2 + path
  M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2) — if it
  already matches, don't touch it.
- Pin state: the button currently shows pin vs pin.fill for pinned/
  unpinned. With a stroke-only lucide pin you must keep the two states
  VISUALLY DISTINGUISHABLE — e.g. pinned = filled version of the same
  path (fill with currentColor) vs unpinned = stroked only. Your call
  which is clearest; must be obvious at a glance.
- Context-menu items (overflow menu labels) are out of scope.
- No new files unless genuinely cleaner; if added, register in pbxproj.

## Verification gate (required — run it yourself, quote your own output)

1. `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug build 2>&1 | grep -E "(warning|error)" | grep -i cardchrome` → must print nothing.
2. `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug test 2>&1 | tail -5` → `** TEST SUCCEEDED **`, 152 tests, 0 failures.
3. Render the footer offscreen at 8× like last time (both normal and
   compact sizes, pin in both states) and check all three glyphs read as
   one lucide family; save the PNG to /tmp/ so the operator can view it.

## Handoff

Commit on feature/horizontal-scroll, message states what changed.
Report: files changed, your own build/test output, the preview PNG path,
and any deviation. Final visual judgment goes to the user.

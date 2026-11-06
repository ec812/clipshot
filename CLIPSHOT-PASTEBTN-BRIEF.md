# UI: paste button — drop the blue primary styling, match its siblings

Project root: /Users/ernest/projects/clipboard (this IS the working directory)
Branch: feature/horizontal-scroll (stay on it).

## Request

The paste footer button renders blue (accent background + accent border)
because it's declared `primary: true`. The user wants it to look like the
other two buttons (copy, pin) — same neutral background/border treatment,
same hover behaviour as its siblings.

## Scope

- Clipshot/UI/CardChrome.swift only: the paste `iconButton(...)` call
  (the one with `help: "Paste item"`) — remove the primary styling so all
  three footer buttons share the neutral look.
- If the `primary` parameter of FooterIconButton becomes entirely unused
  after this, you may remove the dead parameter — but only if nothing
  else passes it; check first. If other call sites exist, leave the
  parameter alone and just stop passing `true`.
- Do not change glyph shapes, spacing, sizes, hover states, or any other
  button. Context menu / overflow out of scope.

## Verification gate (run yourself, quote your own output)

1. `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug build 2>&1 | grep -E "(warning|error)" | grep -i cardchrome` → must print nothing.
2. `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug test 2>&1 | tail -5` → `** TEST SUCCEEDED **`, 152 tests, 0 failures.
3. Re-render the footer offscreen at 8× (normal + compact) like the last
   two times and save to /tmp/ — all three buttons must now look
   uniform (no blue fill/border on paste). Report the PNG path.

## Handoff

Commit on feature/horizontal-scroll, message states what changed.
Report: files changed, your own build/test output, PNG path.

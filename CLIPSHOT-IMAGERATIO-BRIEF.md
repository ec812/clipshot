# UI: image thumbnails — full card width, auto height (no weird aspect)

Project root: /Users/ernest/projects/clipboard (this IS the working directory)
Branch: feature/image-preview (stay on it — your thumbnail work lives here).

## User report (verbatim)

"The aspect ratio of the image is very weird. Use full width of the card,
height should be auto."

## What's wrong

Both image previews use a FIXED height with `.fill` + `.clipped()`:
- `.image` preview in ItemCard: `frame(height: compact ? 46 : 78)` +
  aspectRatio(.fill) + clipped — crops any image that isn't ~3:1.
- The `.file` thumbnail helper you added in 939b6b1 (same pattern) —
  Finder-copied images get the same cropped/distorted-looking result.

## Required behavior

- Thumbnail spans the FULL inner width of the card (edge-to-edge within
  the preview area, same horizontal treatment the color fill gets is
  fine — your call on exact insets, but width must be full).
- Height = derived from the image's true aspect ratio (auto). No fixed
  46/78. No cropping, no distortion — the whole image is visible.
- Applies to BOTH `.image` previews and `.file` image thumbnails (they
  should share one helper if not already).
- Compact + normal, light + dark all correct.
- Edge consideration: a very tall image (e.g. 1000×3000 screenshot)
  would make an unbounded card. Per the user's wording height is AUTO —
  do NOT silently clamp; instead pick sensible SwiftUI sizing (e.g.
  ideal height from aspect ratio) and if you believe a cap is genuinely
  necessary for pathological cases, implement a generous one and FLAG it
  in the report as a deviation for the user to confirm or remove.
- Color cards, code text, other kinds: untouched.

## Verification gate (your own output, quoted)

1. `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug build 2>&1 | grep -E "(warning|error)" | grep -iE "itemcard|clipimage"` → nothing.
2. `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug test 2>&1 | tail -5` → `** TEST SUCCEEDED **`, 217 tests, 0 failures (add/adjust tests if geometry is testable; if the aspect-ratio math is extractable as a pure function, test it).
3. Offscreen render PNGs in /tmp/ proving it: at minimum three aspect
   ratios — wide (e.g. 1600×400), standard (1600×900), tall (600×1800) —
   for both `.image` and `.file` cards, normal + compact. Each must show
   the full uncropped image at full width. State what they show.

## Handoff

Commit on feature/image-preview, message states what changed. Report:
files changed, your own build/test output, PNG paths, any deviation
(e.g. the tall-image decision), remaining manual checks.

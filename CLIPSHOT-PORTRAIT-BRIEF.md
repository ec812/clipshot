# UI: thumbnails — landscape full-width/height-auto, portrait height-capped/width-auto

Project root: /Users/ernest/projects/clipboard (this IS the working directory)
Branch: feature/image-preview (stay on it). Current tip: 2179c04.

## User report (verbatim)

"Good point, when it is tall (portrait), width should be auto too."

## Meaning

Follow-up to the uncapped-tall deviation you flagged. Desired behavior:

- **Landscape / wide images**: full card width, height from aspect
  ratio (exactly as 2179c04 does now).
- **Portrait / tall images**: do NOT span full width and do NOT make an
  unbounded card. The card height stays bounded (pick a sensible cap —
  e.g. a portrait thumbnail should not make the card dramatically
  taller than other cards; your call on the number, normal + compact
  can differ), and the WIDTH becomes auto (derived from aspect ratio),
  so a 600×1800 image renders as a correctly-proportioned narrow
  thumbnail at the cap height instead of a 1008pt-tall slab.

In other words: contain within maxWidth = full inner width × maxHeight =
chosen cap, aspect preserved, whole image visible (no crop), thumbnail
centered or leading-aligned within the preview area (pick one, be
consistent with the card's alignment).

Square images: either dimension may decide — just be consistent at the
boundary; pick the rule (e.g. height cap wins at/after 1:1) and test it.

## Constraints

- Keep `thumbnailHeight(for:)`-style logic as a pure, unit-tested
  function — extend it (e.g. return both width and height for the
  bounded box) rather than moving math back into the view.
- Corner-marker evidence must still show ALL FOUR corners + label for
  portrait: proving nothing is cropped in the new capped form.
- Both `.image` and `.file` previews. Normal + compact, light + dark.
- Color/text/code cards untouched.

## Verification gate (your own output, quoted)

1. `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug build 2>&1 | grep -E "(warning|error)" | grep -iE "itemcard|cardchrome|clipimage"` → nothing.
2. `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug test 2>&1 | tail -5` → `** TEST SUCCEEDED **`, 218 existing + any new, 0 failures. NOTE: if you hit `Command CodeSign failed` / "code object is not signed at all" on the xctest subcomponent, that's a stale-DerivedData flake — run `xcodebuild … clean` then retest, and say so in the report.
3. Re-render the evidence grid: wide/standard/tall/square × image/file
   × normal/compact. State per-variant the rendered width×height. The
   tall 600×1800 must now be capped (state the cap you chose) with all
   four corner markers visible.

## Handoff

Commit on feature/image-preview, message states what changed. Report:
files changed, your own build/test output, chosen cap + boundary rule,
PNG paths, deviations.

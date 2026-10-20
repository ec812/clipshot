# Feature: color items fill the card content with the color + show the color values

Branch: create `feature/color-card-fill` from main, commit there (report branch name), do NOT commit to main.

User requirement (verbatim): "make sure colors are shown as color if it is hex, rgba, rgba, hsl etc, make sure the color is taking up the whole card content (not bg) and shows the color values in the card"

Interpretation (build exactly this):
1. Scope: items whose kind is `color` (whole trimmed clipboard parses as hex / rgb() / rgba() / hsl() / hsla() / oklch / oklab / named — the existing ClipboardColorParser set).
2. The card's CONTENT AREA (the preview region currently used for text/OG image) is entirely FILLED with the parsed color — a full-bleed block of that color. This is the content fill, NOT a border/background wash and NOT a tiny swatch. Card border can stay the app accent; the inner content area is pure color.
3. The color values text (the exact original copied string, e.g. `#a51a15`, `rgba(165, 26, 21, 0.8)`) must be visible IN the card — render it overlaid on the color fill (or in a chip strip at the bottom of the fill, your call), choosing foreground for readability via a luminance test (WCAG-style relative luminance: white text on dark colors, black text on light colors). Keep the source-app icon visible as today.
4. Also keep the raw text as the searchable/preview text in list metadata (search by `a51a15` must still work).
5. Both timeline modes: full size and compact — in compact the fill is shorter but still clearly a solid color block with the values legible (shrink font, don't drop the text).
6. No Shorten/QR actions on color items (already the case — keep).

## Tests / evidence
- Extract the luminance→foreground choice into a pure function and test it: black-on-white-ish for `#ffffff`, white for `#000000`, `#a51a15` (dark) → white text, `khaki`/`lightyellow` → black text.
- Gate: `xcodebuild -scheme Clipshot build` + `xcodebuild -scheme Clipshot test` pass on the branch.
- Screenshot evidence: launch, copy `#a51a15`, `rgba(30,144,255,0.6)`, `hsl(120,60%,50%)`, `#f5deb3` and show them in the timeline → save to Docs/verify-color-cards.png. State honestly what the screenshot shows (color fills, text readable) — vision-verifiable claims only.

## Constraints
Same as always: workspace-only, no global installs, no fabricated results. Final message: branch name, files changed, test counts, build result, deviations.

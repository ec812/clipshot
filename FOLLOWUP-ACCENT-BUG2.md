# Re-open: per-app card accents are NOT visibly rendering (verification claim doesn't match evidence)

Your final message on the accent task claimed the overlay render proves per-app wiring ("Safari blue, Finder blue, Notes yellow, Xcode blue, Brave orange-red"). I analyzed the committed screenshot Docs/verify-accents.png with an independent vision pass, twice, asking specifically about subtle border/background hues:

- Card 1 (Brave, hash text): red visible — but only as left-edge/outline, reads as the SELECTION indicator.
- Cards 2-5 (Safari, Notes, Mode, Finder): "exactly the same neutral gray, no subtle blue/yellow/orange hues visible."
- Conclusion from the image: red selection state is the ONLY color differentiation. No per-app tinting is visible anywhere.

Separately, the user's original complaint was that ALL cards show red "which is not the color of the app."

So either (a) accents load async and your screenshot was taken before they resolved, (b) the tint opacities (0.05 background) are literally invisible in dark mode, (c) the accent lookup returns nil in the live view path even though the direct diagnostic printed colors, or (d) the wiring in ItemCard really is broken for non-selected cards. Find out which — reproduce, don't re-assert.

## Required
1. Instrument or debug the LIVE path: log `AppIconProvider.accent(for:)` results per bundle id at render time (temporarily), launch the app with synthetic items from ≥4 apps, and capture the log. Report the actual accent colors that reach ItemCard.
2. Fix the root cause(s). If opacity is the issue, the user's original request was explicit: "the card should use the main color of the accent of the app icon" — make the app accent clearly visible on the card (border + subtle background wash; enough that a human instantly tells Safari cards from Notes cards in dark mode). This is a visibility spec, not a whisper: aim for a clearly perceptible border tint (~0.5-0.8 opacity border using the accent, background wash ~0.10-0.15), while keeping selected-state visually distinguishable from unselected.
3. Make the async path deterministic for capture: after `ensureLoaded`, accents should be present (memory or disk) before/shortly after first paint. If there's a race where cards render with nil accents and don't refresh, fix it (the `revision` bump should trigger the re-render — verify it actually does through the observed object chain: AppState -> TimelineView -> ItemCard).
4. Re-verify with a NEW screenshot (Docs/verify-accents-v2.png): synthetic timeline with items from ≥4 apps, taken only after accents resolve (wait/poll until the provider reports all bundle ids loaded). In your final message, state the per-card border colors you can confirm from that screenshot.
5. Keep the hue regression tests; add one that pins the RENDERED tint color for a given accent if testable without a full UI harness (e.g. extract the tint-computation into a pure function and test it).
6. Gate: `xcodebuild -scheme Clipshot build` + `xcodebuild -scheme Clipshot test` pass. Commit on main: "Fix visible per-app card tinting: <actual root cause>". Do not claim visual confirmation beyond what the screenshot actually shows — if the tints still don't show, say so.

Same constraints: workspace-only changes, no global installs, no fabricated results.

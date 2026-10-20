# Clipshot Card Restyle — Design

Date: 2026-10-20
Status: approved for implementation planning
Scope: `ItemCard` chrome only

## Goal

Make Clipshot's clipboard cards read like Paste cards: the source-app icon is large and at the top, app identity is the first thing the eye lands on, and the card has a stable action footer instead of a tiny bottom metadata row. The existing per-kind previews (text, URL/OG, image, file, color) remain.

The visual direction was selected in the design companion:

- Header: tinted app band, 40 px icon, app name, type + relative time.
- Band tint: per-app accent (Safari blue, Notes yellow, Terminal neutral).
- Color cards: same per-app band above the full-bleed color swatch.
- Width: keep the 360 pt minimum.
- Actions: persistent icon footer with copy, paste, pin, and overflow.
- Structure: composable chrome (`CardBand` / preview / `CardFooter` + pure `CardChromeStyle`).

## Card anatomy

```
┌─────────────────────────────────────┐
│ [40 px app icon]  Safari             │  per-app tinted band
│                   LINK · 2m ago      │
├─────────────────────────────────────┤
│                                     │
│            content preview          │
│                                     │
├─────────────────────────────────────┤
│ [copy] [paste] [pin] [⋯]             │  persistent footer
└─────────────────────────────────────┘
```

### Band

- Full width of the card, above the preview.
- 40 px source-app icon, rounded 10 px, with a subtle shadow.
- App name: 13 pt semibold, one line, truncating.
- Secondary line: uppercase kind (`LINK`, `TEXT`, `IMAGE`, `FILE`, `COLOR`, `RICH TEXT`) + ` · ` + relative time. 9.5 pt secondary.
- Trailing status glyphs only when relevant: pinned (filled pushpin), short link (link), snippet (text badge). They are indicators, not buttons.
- Missing icon fallback: `app.fill` in a neutral rounded square. Missing source app: `Unknown`.
- Background: per-app accent gradient over a material base. The accent is strongest at the top and fades toward the body.
  - Dark mode: accent opacities ≈ 0.34 top → 0.06 bottom.
  - Light mode: accent opacities ≈ 0.20 top → 0.04 bottom.
  - Selected: add ≈ 0.06 to the top opacity.
  - Text uses `.primary` so it stays legible on light bands (for example Notes yellow).
- No separate "kind icon" in the band; the kind is text.

### Body

- Neutral card surface; the per-app accent lives in the band and border, not as a full-card wash.
- Content is the existing per-kind preview:
  - Text/RTF: existing text preview and line limits.
  - URL: raw URL first, then OG image/title/description asynchronously; preview request starts after first paint.
  - Image: existing image thumbnail.
  - File: existing file icon + name.
  - Color: full-bleed parsed color with the value overlay; the band sits above it and uses the source-app accent.
- Body padding: 12 pt horizontal, 10–12 pt vertical.
- Cards fill the available timeline height. Preview content flexes and truncates; no vertical scrolling inside a card.

### Footer

- Always visible on every card, selected or not. Space is reserved so selection never changes layout.
- 36 pt high (32 pt compact), top hairline separator, slightly darker than the body.
- Direct icon buttons, 30 × 30 pt (26 × 26 compact):
  - **Copy** — two overlapping rounded rectangles.
  - **Paste** — clipboard glyph; primary accent button.
  - **Pin** — pushpin; reflects pinned state (filled when pinned).
  - **Overflow** — ellipsis.
- Every icon button has a `.help` tooltip and an accessibility label: “Copy item”, “Paste item”, “Pin item”, “More actions”.
- Overflow menu:
  - Paste as Plain Text (text, URL, and rich-text kinds only).
  - Shorten… (URL only).
  - Show QR Code (non-color kinds).
  - Add to Paste Stack.
  - Edit… (text/URL), Rename….
  - Destructive actions stay in the existing right-click context menu.
- The full right-click context menu remains unchanged.
- Footer hints are not shown as text; the icons plus tooltips are the affordance. Existing keyboard shortcuts (↩ paste, ⌘P pin) remain.

### Selection and hover

- Unselected: 1.6 pt per-app accent border at existing `CardAccentStyle` opacity; neutral body.
- Selected: 2.2 pt per-app accent border, band top opacity +0.06; footer stays in place.
- Hover: icon-button background/border brightens; footer remains visible.
- Newly captured cards are selected and scrolled into view (already shipped behavior).

## Sizing and compact mode

- Card width remains **360 pt**.
- Full-card layout when the overlay is **≥ 450 pt**.
- Compact layout when the overlay is below 450 pt or **Always use compact cards** is on:
  - 32 px icon.
  - 50 pt band.
  - Footer 32 pt; icon buttons 26 pt.
  - Band title 12 pt, metadata 8.5 pt.
  - Body fonts reduce by ~1 pt; line limits tighten.
- `OverlayController.compactThreshold`: **210 → 450**.
- `AppSettings.overlayHeight` default: **260 → 460**.
- The settings slider range remains 150–560.
- An existing stored height below 450 (for example 424) renders compact cards until the user resizes. Fresh installs start at 460.
- Full-card vertical budget at a 460 pt overlay: the timeline viewport is ≈360 pt; band ≈58, footer ≈36, card padding ≈20, leaving ≈246 for the preview. This fits the 120:63 OG image plus title and two description lines.

## Structure

New file: `Clipshot/UI/CardChrome.swift`

- `CardBand`
  - Inputs: app icon, source app name, kind, relative time, accent, selected, compact, status flags.
  - Renders the tinted band and status glyphs.
- `CardFooter`
  - Inputs: kind, pinned/hasShortLink state, compact, action closures.
  - Renders direct icons and the overflow menu.
- `CardChromeStyle`
  - Pure, unit-testable resolution of band/footer/icon sizes, band tint opacities, corner radius, and compact thresholds.
  - Reuses `AccentTint` / `CardAccentStyle` where possible.

`Clipshot/UI/ItemCard.swift` becomes:

```
VStack(spacing: 0) {
    CardBand(...)
    preview
    CardFooter(...)
}
.background(cardSurface)
.overlay(cardBorder)
```

- Delete the old `header`, `metadata`, and `actionRow` views.
- Keep the existing `preview` switch and URL preview component.
- Keep the context menu and gesture behavior.
- Keep the app-icon/accent loading in `onAppear`.

Files touched:

- `Clipshot/UI/CardChrome.swift` (new; add to `project.pbxproj` source phase)
- `Clipshot/UI/ItemCard.swift`
- `Clipshot/UI/OverlayController.swift` (compact threshold)
- `Clipshot/Services/AppSettings.swift` (default height)
- `ClipshotTests/CardChromeStyleTests.swift` (new; add to test target)
- `TESTING.md` (manual checklist)
- `Docs/verify-card-restyle.png` (verification render)

## Testing and verification

Automated:

- `CardChromeStyleTests`
  - Full vs compact band height, footer height, icon size, footer button size.
  - Band tint: selected opacity > unselected; dark top opacity > light top opacity.
  - Nil accent falls back to a neutral band.
  - Compact threshold boundary at 450.
- Existing `CardAccentStyleTests`, `ColorCardStyleTests`, and all card/preview tests remain green.
- Gate: `xcodebuild -scheme Clipshot build` and `xcodebuild -scheme Clipshot test`.

Manual visual matrix:

- Text, URL (raw URL first, then OG), image, file, color.
- Selected and unselected; footer does not shift layout.
- Full and compact; 360 pt width.
- Light and dark mode; Notes yellow band remains legible.
- Missing app icon / missing source app.
- Pinned and short-link status glyphs.
- Copy, paste, pin, and every overflow action.
- Existing right-click menu.
- Screenshot `Docs/verify-card-restyle.png`.

## Non-goals

- No timeline, filter, search, or keyboard-navigation changes.
- No card width change.
- No changes to paste engine, database, persistence, or link-preview networking.
- No new actions; existing actions are only reorganized into the footer/overflow.

## Risks and mitigations

- **Existing 424 pt overlays switch to compact.** This is intentional to avoid clipping the new chrome; the user can resize to 460 for full cards. Documented in TESTING.
- **Light-mode band contrast.** Use material-backed bands, lower light-mode accent opacities, and `.primary` text; verify Notes yellow and Terminal gray.
- **Overflow discoverability.** Tooltips, accessibility labels, and unchanged right-click menu keep less-used actions reachable.
- **Long app names.** One-line truncation; icon and kind/time remain visible.
- **Hand-maintained Xcode project.** Adding `CardChrome.swift` and its test file requires explicit `project.pbxproj` source-phase entries.

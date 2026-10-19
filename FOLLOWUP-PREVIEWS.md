# Follow-up task: rich previews — color swatches, OG images, source-app icon accent

Same project: /Users/ernest/projects/clipboard. Keep everything behind existing boundaries (models/services/UI separation, tests for logic).

## 1. Color preview (ClipboardColorParser + swatch in ItemCard)
When copied text parses as a single color value, the item card must render a color swatch preview (large-ish rounded square) plus the original text as label, and the Shorten/QR actions are hidden for color items (no meaning). Also register the color as `NSColor` pasteable on paste (paste should re-copy the original text).
Support at minimum:
- Hex: #rgb, #rgba, #rrggbb, #rrggbbaa (case-insensitive)
- rgb()/rgba(): comma and space syntax, percentages allowed, optional /alpha
- hsl()/hsla(): comma and space syntax, optional alpha
- oklch()/oklab() and lowercase "okchl"-style input the user types (treat OKCHL as OKLCH: L C H, H optional defaults 0)
- Named CSS colors: a reasonable subset (the standard ~148 or at least the 16 basic + transparent)
A "color" item kind = the ENTIRE trimmed clipboard string is one color token (optionally followed by whitespace). Anything else stays text.
Unit tests: at least 20 cases across hex 3/4/6/8, rgb %, rgba alpha float, hsl degrees, oklch round-trip to sRGB within tolerance, rejects mixed content, rejects out-of-range.

## 2. OG image for URL items (OGImageLoader)
For items whose kind is URL, asynchronously fetch the page's Open Graph image:
- HEAD/GET with timeout 5s, max body ~1.5MB for the HTML, parse <meta property="og:image"> (also twitter:image as fallback), then download the image (timeout 10s, max 10MB, only image/* content types).
- Cache: disk cache under ~/Library/Application Support/Clipshot/OGCache keyed by URL hash with a per-entry TTL (default 7 days) and an LRU size cap (~200MB); negative-cache failures for 24h so we don't hammer dead pages.
- Runs off the main thread, results delivered to the UI; card shows the og:image thumbnail (aspect-fill, rounded) with graceful placeholder while loading or on failure. Respect the existing "pause"/privacy mode: no fetches while paused.
- Dedupe in-flight requests; do not refetch items already cached.
- Settings toggle: "Fetch link previews (OG images)" default ON, plus "Clear preview cache" button.
- Tests: HTML parser (og:image present, twitter:image fallback, malformed HTML, relative URL resolution against base), cache TTL/LRU logic with a temp dir, negative cache.

## 3. Source-app icon + accent-tinted cards (AppIconAccent)
- Every item card already shows the source app icon — verify and keep. Fetch via NSWorkspace icon(forFile: bundlePath) (fallback: generic icon when bundle id no longer resolves), cached in memory + on disk by bundle id.
- Extract a dominant accent color from the icon (downscale to ~64px, average the most-saturated sufficiently-opaque pixels; reject near-white/near-black/near-gray), and tint the card's border/hover accent with that color at ~30% opacity so each app's cards are visually distinct. Cache accent per bundle id.
- Color items: card accent = the parsed color itself (it IS the accent), on top of the app accent.
- Tests: accent extraction determinism on a generated solid-color NSImage (red icon → red-ish accent), fallback when image is transparent/empty.

## Constraints (same as before)
- Confine changes to /Users/ernest/projects/clipboard. No global installs. No fabricated results; if something can't work, say so.
- Performance: history scrolling must not block on network or icon extraction (everything async, results cached).
- Gate before claiming done: `xcodebuild -scheme Clipshot build` AND `xcodebuild -scheme Clipshot test` pass.
- Update TESTING.md with: color parse matrix check, OG image fetch on a real URL, offline behavior, cache clear, per-app accent visual check.

## Final message must list
Files changed, exact test pass/fail counts, build result, deviations with reasons.

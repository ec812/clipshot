# Clipshot — Testing

This document covers the automated gate and the manual checklist required for a release candidate.

## 1. Automated gate

Run from `/Users/ernest/projects/clipboard`:

```sh
xcodebuild -scheme Clipshot build
xcodebuild -scheme Clipshot test
```

Latest verified result on this machine (Xcode 27.1, macOS 27.0.1):

- `xcodebuild -scheme Clipshot build` → **BUILD SUCCEEDED**
- `xcodebuild -scheme Clipshot test` → **TEST SUCCEEDED** — 197 tests, 0 failures
  - `HistoryStoreTests` — 19
  - `PrivacyFilterTests` — 10
  - `BitlyBackendTests` — 17
  - `ShortenRulesEngineTests` — 10
  - `PasteStackTests` — 3
  - `ClipboardColorParserTests` — 20
  - `ClipboardPayloadReaderTests` — 7
  - `OGImageParserTests` — 19
  - `OGImageCacheTests` — 8
  - `AppIconAccentTests` — 8
  - `AppIconProviderCacheTests` — 2
  - `CardAccentStyleTests` — 6
  - `CardChromeStyleTests` — 4
  - `ColorCardStyleTests` — 8
  - `SingleInstanceGuardTests` — 1
  - `ResizeHandleTests` — 2
  - `HorizontalScrollWheelTests` — 6
  - `ItemCardClickTests` — 2
  - `CodeDetectorTests` — 24
  - `CodeHighlighterTests` — 14
  - `CodeHighlightStoreTests` — 7

Note: Xcode prints unrelated `CoreDevice` / `CoreSimulator` warnings on this machine ("CoreSimulator is out of date"). They concern iOS device support and do not affect macOS builds or tests.

### Automated coverage

| Area | What is asserted |
| --- | --- |
| `HistoryStore` | insert, hash dedupe + timestamp bump, FTS5 prefix search, punctuation-safe queries, kind/bundle filters, retention (pinned kept), pinboards, short-link cache, rule ordering, edit/delete, WAL journal mode + 5 s busy timeout, file reopen persistence, migration idempotency, WAL-present reopen without recreation, I/O-error recovery on the same file, corrupt-WAL leaves the database file intact |
| `PrivacyFilter` | ignore list, transient/auto-generated markers, concealment markers, pause expiry, resume, live ignore-list updates |
| `ClipboardPayloadReader` | text/color/URL/file classification, Finder image copies keep File kind, image pathname strings (existing image, missing file, non-image, directory, prose) classify correctly, URL capture path is synchronous and does not fetch previews, image payload persistence from a background-safe pasteboard snapshot |
| `PasteEngine` | File items write `public.file-url`, image items write `public.png`, and the short-link text override applies only to URL short links |
| `SingleInstanceGuard` | second lock acquisition fails, pid is written, lock can be reacquired after release |
| `BitlyBackend` | POST `/shorten` (Bearer header, `long_url`, `domain`, `group_guid`, cache), POST `/bitlinks` custom-slug path, 401 `INVALID_ARG_ACCESS_TOKEN`, 404, `BRANDED_LINK_MONTHLY_LIMIT_EXCEEDED`, `DNS_CONFIGURATION_ERROR`, validation, 503, missing token, PATCH update, DELETE, GET `/user` verify, clicks parsing + cache update, capabilities |
| `ShortenRulesEngine` | URL/host globs, source app matching, priority order, disabled rules, slug tokens and sanitization, determinism |
| `PasteStack` | FIFO order, count/active state, clear |
| `ClipboardColorParser` | hex 3/4/6/8, rgb/rgba comma + space, percentages, alpha, hsl/hsla, oklch/okchl/oklab → sRGB round-trip, named subset, mixed-content and out-of-range rejection |
| `OGImageParser` | `og:image` variants/`og:title`/`og:description`, `twitter:*` fallbacks (including an invalid OG image), `<title>` and `<meta name="description">` fallbacks, precedence, partial metadata, attribute order/case, relative URL resolution, entities, whitespace, malformed markup, non-HTTP rejection |
| `OGImageCache` | full image + title/description record round-trip, metadata-only record, store/lookup, 7-day TTL, 24-hour negative cache, positive↔negative replacement, LRU eviction under a byte cap, clear |
| `CardAccentStyle` | unselected border opacity ≥ 0.5 and wash ≥ 0.10, selected stronger than unselected, blue/yellow composited hue preserved over a dark card background |
| `CardChromeStyle` | full/compact band, icon, footer, and button dimensions; selected/dark band tint strength; nil-accent fallback; 450 pt compact boundary |
| `ColorCardStyle` | WCAG relative luminance → black/white foreground: white → black, black → white, #a51a15 → white, khaki/lightyellow → black, translucent blue composited over dark/light card backgrounds |
| `CodeDetector` | Swift/JS/TS/Python/JSON/shell/SQL/HTML/CSS/C-family positives, indented and single-line snippets, prose/email/dashed-text/URL/date negatives, CRLF, bounded 16 KB prefix |
| `CodeHighlighter` | keyword/type/string/number/comment token kinds, HTML tag/attribute tokens, CSS property names, unterminated strings, tab normalization, text preservation, 2,000-char/40-line bounds, light/dark theme colors |
| `CodeHighlightStore` | one detection per hash, both color-scheme variants cached, one revision bump, in-flight dedupe, override precedence and persistence, forced generic fallback, non-text/empty items ignored |

## 2. Manual checklist

Complete every item on a real Mac (simulators do not exercise menu-bar, full-screen or Accessibility behavior). Mark each item when verified.

### Setup
- [ ] Build and launch `Clipshot.app` from DerivedData (`open ~/Library/Developer/Xcode/DerivedData/Clipshot-*/Build/Products/Debug/Clipshot.app`).
- [ ] Grant Accessibility when prompted (System Settings → Privacy & Security → Accessibility).
- [ ] Open Settings → Integrations and save a valid **Bitly access token** (create one at https://dev.bitly.com/). Shortening features only; the clipboard manager works without it.
- [ ] Confirm the token verifies with Test connection (GET /user) and the provider picker shows **Bitly**.
- [ ] Confirm the menu-bar icon is present and `⌘⇧V` opens the bottom bar.

### Clipboard capture — copy from at least 5 apps
- [ ] Copy text in **Safari** (select text → ⌘C) → appears in the timeline with Safari as source.
- [ ] Copy in **Terminal** → appears.
- [ ] Copy a file in **Finder** → appears as a File card with the filename.
- [ ] Copy an image in **Preview** (select region → ⌘C) → appears as an image card; preview renders.
- [ ] Copy an image file in **Finder** (⌘C) → the File card shows the image thumbnail, not the filename or path. Paste into Finder (⌘V) still pastes the file.
- [ ] Image thumbnails preserve aspect ratio without cropping: landscape images span the full inner width with auto height; portrait images are height-capped (220 pt normal / 200 pt compact) with auto width and leading alignment. Test wide, standard, tall and square images.
- [ ] Select an image file in Finder and use **⌥⌘C Copy as Pathname**, then open the timeline → the card shows the image thumbnail (File kind), not the path text.
- [ ] Copy a path to a non-image file (e.g. a PDF) or prose containing a path → unchanged (text/File as before, no thumbnail).
- [ ] Copy rich text from **Notes** → appears as Rich Text, plain text preview visible.
- [ ] Copy a URL from any app → appears as a Link card; `⌥⇧S` becomes available.
- [ ] Re-copy the exact same content → no duplicate card; the existing item moves to the front.

### Code highlighting
- [ ] Copy a multi-line **Swift** snippet from Xcode → the card preview is monospaced and syntax-highlighted, with line breaks and indentation preserved inside the 4/7-line limit.
- [ ] Repeat for **JavaScript/TypeScript**, **Python**, **JSON**, a shell script, **SQL**, **HTML** and **CSS** → each is highlighted with the expected language colors.
- [ ] Copy a prose paragraph, an email with punctuation, and dashed prose → no highlighting; the preview stays in the existing SF Pro style.
- [ ] Right-click a highlighted code card → **Show as Plain Text**; right-click a prose card → **Highlight as Code**; relaunch and confirm both overrides stick.
- [ ] Check compact and full overlay heights, and light and dark appearance.
- [ ] Copying several items in a row remains responsive (detection runs lazily off-main, never on the capture hot path).
- [ ] Reference capture: `Docs/verify-code-highlight.png`.

### Pasting — into at least 5 apps
- [ ] Press `↩` on a text item with **TextEdit** focused → text is inserted at the cursor and the previous clipboard is restored.
- [ ] Paste into **Notes** → works.
- [ ] Paste into a **Safari** form field → works.
- [ ] Paste into **Terminal** → works.
- [ ] Paste into **Mail** compose window → works.
- [ ] Copy rich text, select it, press `⇧↩` → target receives plain text (formatting stripped).
- [ ] Press `↩` with rich text (not plain) → target receives formatting.
- [ ] Press `⌘1`–`⌘9` → quick-pastes the card at that position.

### Accessibility permission-denied fallback
- [ ] Remove Clipshot from System Settings → Accessibility, relaunch.
- [ ] Press `↩` on an item → the overlay closes, the item is on the clipboard, and the toast says Accessibility is needed.
- [ ] Verify `⌘V` in the target app pastes the item.
- [ ] Re-grant Accessibility, relaunch, confirm direct paste works again.

### Overlay behavior
- [ ] Enter full-screen video in Safari or QuickTime, press `⌘⇧V` over it → the bottom bar appears above the full-screen content without switching Spaces.
- [ ] With two displays, put the pointer on the secondary display, press `⌘⇧V` → the bar opens on that display.
- [ ] Drag the top handle up/down → the panel resizes smoothly with no flicker, height changes; below the compact threshold cards switch to compact layout. Height persists after releasing the drag.
- [ ] Press `Esc` → overlay hides. Click outside → overlay hides.
- [ ] Type in the search field → results narrow with FTS; clear the field → full history returns.
- [ ] Use the type and source-app filter menus and the Pinned/pinboard chips.
- [ ] Type a multi-word query in the search field → spaces are entered into the query; Backspace deletes query characters instead of history items.
- [ ] With a non-empty query, press `←`/`→` → the text insertion point moves; it does not change the selected card. With an empty query, `←`/`→` navigate cards.
- [ ] Press `⌘⌫` with a search query present → the selected history item is deleted.
- [ ] Press `⌘Y` on a text item and an image item → Quick Look opens the preview.
- [ ] Press `⌫` with the search field not focused (click a card first) → the selected item is deleted.

### Color previews
Copy each value below, then open the timeline. Each color item's entire content area must be filled with the parsed color (not just a small swatch), with the exact original string overlaid at the bottom. Foreground text must be black or white chosen by WCAG relative luminance; Shorten and QR must be absent. `Docs/verify-color-cards.png` shows `#a51a15`, `rgba(30,144,255,0.6)`, `hsl(120,60%,50%)`, and `#f5deb3` as full fills with legible values.

| Input | Expected |
| --- | --- |
| `#f00` | red |
| `#f008` | translucent red |
| `#ff0000` | red |
| `#FF000080` | translucent red |
| `rgb(255, 0, 0)` | red |
| `rgb(100% 0% 0% / 50%)` | translucent red |
| `rgba(255, 0, 0, 0.25)` | translucent red |
| `hsl(120, 100%, 50%)` | green |
| `hsla(240, 100%, 50%, 0.25)` | translucent blue |
| `cmyk(0, 100, 100, 0)` | red (CMYK components use the 0–100 scale) |
| `cmyka(0, 100, 100, 0, 0.5)` | translucent red |
| `FF5733` | orange (bare six-digit hex; must mix a hex letter and a digit) |
| `oklch(0.62796 0.25768 29.234)` | red |
| `okchl(0.62796 0.25768 29.234)` | red (typo alias) |
| `red` / `ReBeCcApUrPlE` | named CSS colors |
| `transparent` | fully transparent color fill |
| `hello #ff0000` | **text**, not a color |

- [ ] Copy a color value from a rich source that also offers an RTF flavor (Safari selection, browser devtools, a design tool) → still a color card; the RTF flavor must not win.
- [ ] Copy `20240101`, `123456`, `deadbeef` or `facade` → stays a text item (bare hex must mix a hex letter and a digit).
- [ ] Copy `#3498db`, paste into TextEdit with `↩` → the original text `#3498db` is pasted.
- [ ] Paste the same color into a color-aware app (e.g. a design tool color field) → the `NSColor` representation is accepted.
- [ ] Search for `a51a15` / `f5deb3` → the color items are found (the original text remains the indexed/preview text).
- [ ] Resize to compact mode → the color block is shorter but still a solid fill with legible values.
- [ ] Copy `#ff0000 extra text` → stays a text item (no fill).
- [ ] Press `⇧↩` on a color item → plain text of the original value is pasted.
- [ ] Confirm the content fill (not just the card border/background) is entirely the parsed color, and the source-app icon remains visible.

### Link previews (OG image + title + description)
- [ ] Copy a real article URL whose page has `og:image`, `og:title` and `og:description` (e.g. https://www.apple.com/newsroom/2024/06/introducing-apple-intelligence-for-iphone-ipad-and-mac/) → the card shows the image, a bold one-line title, and a secondary two-line description. Reference capture: `Docs/verify-og-full.png`.
- [ ] Copy a URL that only has `twitter:image` / `twitter:title` / `twitter:description` → those values appear.
- [ ] Copy a URL with only `<title>` and `<meta name="description">` → the plain-head values appear.
- [ ] Copy a URL with only a title (no image/description) → the title and image placeholder appear; missing fields are simply omitted.
- [ ] Copy a URL with no OG/Twitter/head metadata → the URL text is shown; no crash.
- [ ] Copy the same URL twice → only one page and one image fetch are made (inspect the cache directory / network).
- [ ] Quit and relaunch Clipshot, copy the same URL → image, title and description appear from disk cache without a network fetch.
- [ ] Settings → General → turn **Fetch link previews (OG images)** off → new URL cards show the fallback URL and no network requests are made; turn it back on → previews load.
- [ ] Offline behavior: disconnect the network, copy a URL not yet cached → fallback remains, the UI stays responsive, and no fetch spins forever.
- [ ] Reconnect and copy that same URL within 24 hours → negative cache still shows the fallback (by design). Press **Clear preview cache**, then copy again → it loads.
- [ ] Settings → General → **Clear preview cache** → cached previews disappear and refetch when cards next appear.
- [ ] Pause capture (menu bar), copy a new URL, open the timeline → no OG fetch occurs while paused; resume and reopen → the fetch starts.

### Capture latency
- [ ] With the timeline open, copy a short unique string → the new card appears immediately and is selected/scrolled into view (no manual refresh).
- [ ] Copy a URL → the raw URL is the first content rendered; the OG image/title/description enrich the card afterward without delaying the item.
- [ ] Measured on this machine with a simulated pasteboard write: p50 **≈79 ms** from write to the item being published in the visible list (samples 36.5, 41.8, 76.8, 80.9, 141.0, 151.6 ms). Clipboard polling is 0.1 s with a 0.01 s tolerance. A user-initiated `ProcessInfo` activity suppresses App Nap while monitoring so the timer is not throttled in the background; idle CPU measured 0.0–0.3%.
- [ ] URL vs text copy→card-onAppear (two pairs each): before the visibility change URL 75.0/59.1 ms vs text 62.6/59.7 ms; after URL 78.1/121.4 ms vs text 89.5/103.0 ms. There is no URL-specific insert/network delay; both are under 150 ms.

### Database persistence across rebuilds
- [ ] Launch build A; copy three unique text items; confirm all three cards.
- [ ] Stop the app with Xcode Stop (SIGKILL), then build B and relaunch.
- [ ] Search for the unique text prefix → all three items are still present; the launch log prints the same `~/Library/Application Support/Clipshot/clipshot.sqlite` path for both builds.
- [ ] Confirm there is no `SQLite error 10` / `PRAGMA query_only` disk-I/O message in Console during the search.
- [ ] Do not replace or unlink `clipshot.sqlite`, `-wal`, or `-shm` while the app is running. If an external process does, Clipshot now closes and reopens the same file (no deletion/recreation) and surfaces a red error banner if reopening fails.

### Card chrome (Paste-style)

- [ ] Full-height overlay (460 pt): every card shows a 40 px source-app icon in a per-app tinted band at the top, the app name, and `TYPE · time`.
- [ ] The bottom app-metadata row is gone; the footer is always visible with copy, paste, pin, and overflow icons.
- [ ] Selecting another card does not shift the footer or content (no layout jump).
- [ ] Color cards show the same per-app band above a full-bleed parsed-color swatch; the value text remains readable.
- [ ] URL cards paint the raw URL first; the OG image/title/description enrich the card afterward.
- [ ] Full layout at ≥450 pt; compact layout below 450 pt or with “Always use compact cards” enabled.
- [ ] Light mode: Notes yellow and Terminal gray bands remain readable.
- [ ] Copy, paste, pin, and every overflow action (plain paste, shorten for URL, QR, paste stack, edit/rename) work.
- [ ] The right-click menu still exposes pinboards and destructive actions.
- [ ] Reference capture: `Docs/verify-card-restyle.png`.

### Source-app icon + accent
> A timeline containing clips from only one app legitimately shows that app's accent on every card. For example, a Brave-only history is orange-red — this is not a generic red tint. Capture from at least two apps before judging per-app accents. `Docs/verify-card-restyle.png` shows the current band treatment; `Docs/verify-accents-v2.png` is the earlier wash-based diagnostic.

- [ ] Copy text from at least 4 apps with distinct icons (Safari, Notes, Terminal, Preview) → each card shows a clearly visible tinted top band and matching border; the body stays neutral.
- [ ] Safari/Finder cards have a clearly blue band/border; Notes has a clearly yellow band/border; Terminal (gray/black icon) stays neutral.
- [ ] Verify the selected card is still distinguishable: stronger band tint, full-opacity accent border, and thicker stroke than unselected cards.
- [ ] Copy a color value → its card body is the full-bleed parsed color with a readable value; the band and border use the source-app accent.
- [ ] Quit and relaunch, open the timeline → icons and accents appear from cache without a visible delay.
- [ ] Verify the cache version marker at `~/Library/Application Support/Clipshot/AppIcons/cache-version` reads `v2`; legacy `*.png`/`*.accent` entries from older builds are gone (one-time migration).
- [ ] Remove/uninstall an app whose clipboard item is still in history (or use an item with an unknown bundle id) → a generic app icon is shown instead of a blank.

### Lifecycle / single instance
- [ ] Start Clipshot, then start the same binary/app again without quitting the first → the second process logs `another instance is already running; activating it and exiting`, exits immediately, and exactly one Clipshot process remains.
- [ ] Verify `~/Library/Application Support/Clipshot/clipshot.lock` contains the surviving process id.
- [ ] Verify the survivor's log shows `registered hotkey toggleOverlay`, `shorten`, and `showQR`; open Settings → Hotkeys and confirm no conflict warning.
- [ ] Post `com.ernest.clipshot.show-overlay` via `DistributedNotificationCenter` (or press `⌘⇧V` when Accessibility is granted) → the survivor opens the timeline panel; it must not require a second instance.
- [ ] Confirm the database uses WAL and a busy timeout: `sqlite3 ~/Library/Application\ Support/Clipshot/clipshot.sqlite "PRAGMA journal_mode; PRAGMA busy_timeout;"` → `wal` and `5000`.
- [ ] If the app is launched from Xcode repeatedly, confirm old processes are not left behind (`pgrep -fl "Clipshot.app/Contents/MacOS/Clipshot"` shows one).

### Pinboards and snippets
- [ ] Create a pinboard (`+` chip) with a name and color.
- [ ] Add an item via right-click → Add to Pinboard; filter by the pinboard → item appears.
- [ ] Pin an item (`⌘P`) → it sorts to the top and is excluded from retention.
- [ ] Press `⌘N`, save text → a new item appears; `⌘E` edits it, `⌘R` renames it.
- [ ] Set retention to 7 days in Settings, restart → unpinned items older than 7 days are gone; pinned items remain.

### Auto-shorten rule fires exactly once
- [ ] Settings → Integrations → Add rule: URL pattern `*example.com*`, slug template `test-{word}`, auto-copy on, enabled.
- [ ] Copy `https://example.com/article` from Safari.
- [ ] Open the timeline → the original link has a short-link badge; a new history item contains the short URL; the short URL is on the clipboard.
- [ ] Menu bar → Recent Links shows exactly **one** new entry for that copy.
- [ ] Copy the same URL again → the timeline bumps the original item but **no second link** is created (rule only fires on new captures).
- [ ] Shorten a link manually (`⌥⇧S`) with a custom slug → sheet succeeds (POST /bitlinks), short URL copied, recent links updated.
- [ ] Try a slug that already exists → Bitly validation message is displayed (no crash).

### Bitly click analytics
- [ ] Open Menu bar → Recent Links → a cached link → “Refresh Clicks”.
- [ ] The link title shows a click count after refresh; the count matches the all-time daily timeline from GET `/bitlinks/{bitlink}/clicks?units=-1&unit=day`.
- [ ] “Open Short Link”, “Open Destination” and “Open Bitly Analytics” open the right URLs.
- [ ] Refresh a link that was deleted in Bitly → a clean 404 error is shown, no crash.
- [ ] In Settings, clear the token and refresh → the app explains a token is required.

### QR
- [ ] Select a URL and press `⌥⇧Q` → QR window opens.
- [ ] Scan the QR with a phone camera → opens the correct (short or original) URL.
- [ ] Click "Copy image" → paste into Preview → QR is intact (no interpolation blur).
- [ ] "Save…" writes a PNG that still scans.

### Pause blocks capture
- [ ] Menu bar → Pause Capture → 5 minutes.
- [ ] Copy three different strings in different apps.
- [ ] Open the timeline → none of the three appear; the header shows "Paused".
- [ ] Menu bar → Capture Paused → Resume Now.
- [ ] Copy another string → it appears.

### Privacy
- [ ] Copy a password from 1Password (or add your browser's bundle id to the ignore list) → nothing is captured.
- [ ] Copy from an app whose bundle id is in the ignore list → nothing is captured.
- [ ] Toggle "Skip concealed content" off, copy from a manager that uses `org.nspasteboard.ConcealedType` → content is captured (only do this if intentional).
- [ ] Confirm the database contains no entries while paused or ignored.

### Hotkeys
- [ ] Settings → Hotkeys → click a shortcut, press a new combination → the new shortcut opens the overlay.
- [ ] Assign the same shortcut to two actions → a conflict error is shown.
- [ ] Reset all shortcuts → defaults (`⌘⇧V`, `⌥⇧S`, `⌥⇧Q`) work again.
- [ ] While another app owns `⌘⇧V`, launch Clipshot → the conflict is surfaced instead of crashing.

### Integrations error states
- [ ] Save an invalid Bitly token → Test connection reports rejected (401 `INVALID_ARG_ACCESS_TOKEN`).
- [ ] With a plan at its branded-link limit, shorten to a branded domain → “branded-link monthly limit” is shown (`BRANDED_LINK_MONTHLY_LIMIT_EXCEEDED`).
- [ ] Shorten to a custom domain with broken DNS → a clear DNS configuration error is shown (`DNS_CONFIGURATION_ERROR`).
- [ ] Disconnect the network and shorten → a network error is shown; the app remains usable and history capture continues.
- [ ] Remove the token → timeline works, shorten prompts for a Bitly token.

### Packaging smoke test (release)
- [ ] `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Release build` succeeds.
- [ ] Launch the Release build, repeat a subset of the checks above.
- [ ] (Requires credentials) run `Scripts/package.sh`, mount the DMG, launch on a clean account, verify Gatekeeper accepts the notarized app.

## 3. Known limitations to verify/accept

- Bitly slugs are immutable — `PATCH /bitlinks/{bitlink}` supports `long_url` and `tags` only (`supportsUpdateSlug == false`); the UI does not offer slug edits.
- Recent Links is Clipshot's local cache (Bitly's list endpoint is group-scoped); links deleted directly in Bitly remain in the cache until manually removed.
- Auto-slug shortening (`POST /shorten`) has no tags field, so configured tags are applied with a follow-up PATCH; if that PATCH fails, the link still exists without tags.
- The custom back-half is sent as Bitly's `keyword` field (the API's name for a custom slug); third-party docs sometimes call it `custom_slug`.
- Launch at login via `SMAppService` requires a signed app placed in `/Applications`; it may fail for ad-hoc Debug builds (the error is surfaced in Settings).
- Pinboards are populated via the context menu ("Add to Pinboard"); drag-and-drop onto a pinboard chip is not implemented in v1.
- OG image extraction is regex-based and static: pages that render metadata with JavaScript, block automated requests, or use other rich-preview tags will not preview.
- Negative previews are cached for 24 hours, so a transient offline failure suppresses retries until the TTL expires or the user clears the cache.
- `warnWhenPasteRunning` detects known competing bundle ids (Paste, ShortMenu) but cannot detect every clipboard utility.

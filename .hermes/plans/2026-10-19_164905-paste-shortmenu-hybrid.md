# Plan — macOS native app: Paste × ShortMenu hybrid

Date: 2026-10-19
Workspace: /Users/ernest/projects/clipboard (fresh, empty)
Status: approved — delegated to Command Code (cmd)

## Decisions (Ernest, 2026-10-19)
- **Distribution: direct notarized download** (no Mac App Store in scope). Archive + `notarytool` notarization + DMG in Phase 7; skip sandbox/App Store review concerns.
- **Swappable shortener backend: YES.** Define a `ShortenerBackend` protocol (`createLink`, `updateLink`, `deleteLink`, `listCachedLinks`, capabilities) with a registry so backends are providers, not hard-wired.
- **Correction (Ernest, 2026-10-19, supersedes earlier Short Menu API plan): we do NOT depend on Short Menu's platform/API.** ShortMenu-the-app is a Bitly client (it requires a Bitly API key). We are reverse-engineering ShortMenu's *behavior/UX* (menu bar, auto-shorten rules, hotkeys, recent links, QR), and the actual shortening backend is **Bitly API v4** directly:
  - `POST https://api-ssl.bitly.com/v4/shorten` `{long_url, domain?}` or `POST /v4/bitlinks` when a `custom_slug` is needed; `PATCH /v4/bitlinks/{bitlink}`; `DELETE /v4/bitlinks/{bitlink}`.
  - Auth: `Authorization: Bearer <Bitly access token>` (user's own Bitly account token, stored in Keychain).
  - Token verify: `GET /v4/user`. Click analytics ARE readable: `GET /v4/bitlinks/{bitlink}/clicks` (+ countries/referrers) — so Recent Links can show real click counts, unlike the ShortMenu API.
  - Errors to map: 401 `INVALID_ARG_ACCESS_TOKEN`, 404, `BRANDED_LINK_MONTHLY_LIMIT_EXCEEDED`, `DNS_CONFIGURATION_ERROR`.
  - Rename `ShortMenuClient`/`ShortMenuBackend` → `BitlyClient`/`BitlyBackend`; all `api.shortmenu.com` references removed. Settings labels the provider "Bitly".

---

## 1. Goal

A single macOS-native menu-bar app that combines:

- **Paste (pasteapp.io)** — full clipboard history manager: unlimited history, visual timeline, instant search + filters, pinboards/snippets, quick-paste hotkeys, paste stack, plain-text paste, ignore/privacy rules, preview & edit.
- **ShortMenu (shortmenu.com)** — URL shortener from the menu bar: shorten any copied URL, custom slugs, branded domains, QR codes, auto-shorten rules, custom hotkeys, recent links, analytics.

**The fusion (why this is one app and not two):** the clipboard history becomes the launchpad for link shortening. Copy a URL → it lands in history → one keystroke shortens it (Bitly API v4) → the short link is written back as a new clipboard item, pinned, or QR'd. Auto-shorten rules fire on copy. Everything Paste does, plus a "⇄ Shorten" action on any URL-shaped history item.

Working name: **Clipshot** (placeholder — see Open Questions).

## 2. Spec research (what the two apps actually do)

### Paste — feature inventory
- Runs in background, polls clipboard; saves text, links, images, files, colors; skips transient content and passwords/sensitive apps (configurable ignore list in Settings → Privacy; pause with ⌘T for a duration).
- History window is a **bar across the bottom of the screen**, opens on the active display, drag top edge to resize, auto-switches to Compact Mode when small.
- Keyboard-first: ⌘⇧V opens, ←/→ navigate, Return pastes, ⌘+number Quick Paste, type-to-search immediately, ⌘F filters (content type / source app / device / date range), Space = Quick Look, ⌘E edit in place, ⌘R rename, ⌘N new text item, drag to target app.
- Multi-select paste (⌘/⇧ click), **Paste Stack** (sequential paste of several items), paste-as-plain-text (⇧Return).
- Insert-at-cursor requires **Accessibility permission** (without it, falls back to copy-to-clipboard).
- **Pinboards**: named, colored, persistent, drag items in, shareable (iCloud).
- Preview/edit inline; OCR text-inside-images searchable; Apple Intelligence Writing Tools + next-paste suggestions (macOS 26).
- Sync across Mac/iPhone/iPad via private iCloud; local-first, no servers.
- Price: $2.49/mo or $29.99/yr after 7-day trial.

### ShortMenu — feature inventory
- Menu-bar URL shortener (since 2012, 4.7★ / 600+ App Store ratings).
- **Auto-Short Links**: automatically convert every URL you copy into a short link, with **configurable rules** (when/how it fires).
- Custom hotkeys; recent-links list one click away; custom slugs; bring-your-own domain; QR codes (unlimited); UTM params; social thumbnails; region/device redirects; click analytics (timeline, country, referrer, device).
- Share sheet from any app; iOS/iPad/web apps; integrations (Zapier, Airtable, Make, ChatGPT).
- **Shortening backend: Bitly API v4** (the ShortMenu app itself is a Bitly client): `POST /v4/shorten`, `POST /v4/bitlinks` (custom keyword), `PATCH/GET/DELETE /v4/bitlinks/{bitlink}`, `GET /v4/user` for token verification, and `GET /v4/bitlinks/{bitlink}/clicks` for click analytics. Auth: `Authorization: Bearer <Bitly access token>`. Errors: 401 `INVALID_ARG_ACCESS_TOKEN`, 404, `BRANDED_LINK_MONTHLY_LIMIT_EXCEEDED`, `DNS_CONFIGURATION_ERROR`.
- **Bitly list endpoint is group-scoped**, so Recent Links is locally cached. Click analytics are available (`GET /bitlinks/{bitlink}/clicks`) and shown via “Refresh Clicks”.

## 3. Proposed approach

### Architecture

```
Clipshot.app (Swift 5.10+, macOS 14+, SwiftUI + AppKit where required)
├── App layer
│   ├── MenuBarExtra (status item: pause, settings, recent links, quit)
│   ├── OverlayWindow: NSPanel (.nonactivatingPanel) bottom bar — timeline UI
│   └── Settings (SwiftUI Settings scene)
├── Services
│   ├── ClipboardMonitor    NSPasteboard.changeCount polling + dedupe + type sniffing
│   ├── HistoryStore        SQLite via GRDB, FTS5 full-text index, pinboards
│   ├── PasteEngine         CGEvent-based ⌘V simulation (needs Accessibility)
│   ├── BitlyClient         Bitly v4 REST client, access token in Keychain
│   ├── ShortenRulesEngine  "auto-shorten when…" predicate evaluation
│   ├── QRGenerator         CoreImage CIQRCodeGenerator
│   ├── HotkeyManager       Carbon RegisterEventHotKey (no Input Monitoring TCC)
│   └── PrivacyFilter       ignore-list, password-manager detection, pause timer
└── Models: ClipboardItem, Pinboard, ShortLink, Rule, Settings
```

Key decisions baked in:
- **Local-first, SQLite (GRDB) + FTS5.** No CloudKit/iCloud sync in v1 — it's a huge scope multiplier (conflict resolution, entitlements, iOS twin). Ship Mac-only, sync later.
- **Bitly is the shortening backend via API v4** — we do not reimplement redirect infra, analytics, or branded domains. The user supplies their own Bitly access token once (stored in Keychain). The app stays useful without it (history features degrade gracefully).
- **Paste simulation = CGEvent keydown ⌘V after writing to NSPasteboard**, gated on Accessibility permission, same fallback as Paste (copy-only when denied).
- **Overlay = NSPanel with `.nonactivatingPanel` + `.canJoinAllSpaces` + `.fullScreenAuxiliary`** so it appears over full-screen apps without stealing focus, on the display with the active cursor.
- **Global hotkeys via Carbon `RegisterEventHotKey`** — no Input Monitoring permission prompt.
- Clipboard polling: ~0.3 s `changeCount` check in a background `DispatchSourceTimer`; ignore our own writes; skip when paused.

### The fusion features (the reason to build this)
1. **⌥⇧V timeline** with per-item action row: Copy, Paste, Paste plain, **Shorten ⇄**, QR, Pin.
2. **Shorten action on any URL item** → `POST /v4/shorten` (or `POST /v4/bitlinks` for a custom keyword) → result becomes a new history item (short URL text), original optionally stays; toast confirms.
3. **Auto-shorten rules** (ShortMenu's "Configurable Rules" pattern): e.g. "when copied URL matches `*.medium.com*` → shorten with slug `med-<word>`", "only in apps: Twitter/Mail", "never when password field focused".
4. **Recent Links panel** in menu bar (locally cached from our own API responses + manual edits) with copy-short-URL, open link, and “Refresh Clicks” reading the real Bitly click timeline.
5. **QR on demand** for any URL or short link (CoreImage, render as PNG, drag/share).
6. **Paste Stack** where a URL item pastes as its short version if "prefer short links" is on.

## 4. Step-by-step plan

### Phase 0 — Scaffold (½ day)
- `xcodebuild -list` green: create Xcode project in `/Users/ernest/projects/clipboard/Clipshot/` (app target `Clipshot`, unit-test target `ClipshotTests`).
- Add SPM deps: **GRDB.swift**; nothing else required for v1.
- Wire Info.plist: `NSAccessibilityUsageDescription`, `LSUIElement` (menu-bar-first; optionally prompt "show Dock icon" setting), bundle id `com.ernest.clipshot`.
- CI-local check: `xcodebuild -scheme Clipshot build` must pass from CLI.

### Phase 1 — Clipboard core (1–2 days)
- `ClipboardMonitor`: 0.3 s timer on changeCount; classify payload (text/URL/RTF/image/file/color/attributed); compute content hash for dedupe; skip own writes; respect pause + `PrivacyFilter`.
- `HistoryStore` (GRDB): table `items(id, kind, text, data_path, source_app, bundle_id, created_at, is_pinned, title, short_url, hash)`, FTS5 virtual table over `text + title`; pinboards table; retention setting (keep-forever default = Paste behavior).
- `PrivacyFilter`: bundle-id ignore list (1Password, browser password fields via heuristics), transient-content skip, pause with duration (⌘T menu).
- Tests: `HistoryStoreTests` (insert/dedupe/FTS query/retention), `PrivacyFilterTests`.

### Phase 2 — Overlay UI (2–3 days)
- `OverlayWindow`: NSPanel bottom bar, multi-display aware (open on screen containing mouse), draggable top edge to resize height, Compact Mode under threshold.
- Timeline: horizontal `ScrollView` of `ClipboardItemCard` (preview by kind, source-app icon, relative time), ←/→ selection, type-to-search → FTS5, ⌘F filter chips (kind / source app / date), Space Quick Look (`QLPreviewPanel`), Return paste, ⌘+digit quick paste.
- Menu bar status item with pause, recent links, settings, quit.
- Tests: search-in-FTS + filter query builder (unit); manual checklist for overlay behavior over full-screen apps.

### Phase 3 — Paste engine (1 day)
- `PasteEngine`: save current clipboard → write item → synthesize ⌘V `CGEvent` → restore after 200 ms; plain-text variant writes `public.utf8-plain-text` only; multi-select and **Paste Stack** queue.
- First-run permission flow: detect `AXIsProcessTrusted()`, prompt window with "Open System Settings" button; degrade to copy-to-clipboard when denied.
- Tests: unit-test the queue/state machine (paste sequencing is the bug-prone part); manual test script in `TESTING.md`.

### Phase 4 — Pinboards & snippets (1–2 days)
- Pinboards: create (name + color), drag item → pin, pinned list searchable alongside history, persistent forever regardless of retention.
- "New text item" (⌘N), rename (⌘R), edit-in-place (⌘E) for text items.

### Phase 5 — Bitly integration (2 days) — the differentiator
- `BitlyClient`: `POST https://api-ssl.bitly.com/v4/shorten` with `Authorization: Bearer`, payload `{long_url, domain?, group_guid?}`; `POST /v4/bitlinks` for custom keywords/branded domains; `PATCH/DELETE /v4/bitlinks/{bitlink}`; map 401 `INVALID_ARG_ACCESS_TOKEN`, 404, `BRANDED_LINK_MONTHLY_LIMIT_EXCEEDED`, `DNS_CONFIGURATION_ERROR` to typed errors; cache every successful response into the `short_links` table (our local "recent links").
- Settings → Integrations: Bitly access-token field (Keychain write), default domain, group GUID, default tags, test-connection button (GET /user). Help link: dev.bitly.com.
- **Shorten action**: ⌥⇧S on selected URL item → confirm sheet (slug field, domain picker) → shorten → copy short URL + insert into history with `short_url` set.
- **Rules engine**: declarative `ShortenRule(match: urlPattern | sourceApp | daypart, action: domain/slugTemplate/autoCopy)` — SQLite-stored, evaluated in `ClipboardMonitor` pipeline, fully configurable UI.
- **QR**: `CIQRCodeGenerator` → NSImage, share/drag/export; available for original and short URLs.
- Recent Links menu: cached list → copy / open / refresh clicks (GET `/bitlinks/{bitlink}/clicks`), open Bitly.
- Tests: `BitlyBackendTests` (URLProtocol mock — 200 shorten, 401 `INVALID_ARG_ACCESS_TOKEN`, 404, `BRANDED_LINK_MONTHLY_LIMIT_EXCEEDED`, custom keyword via `/bitlinks`, clicks refresh), `ShortenRulesEngineTests` (pattern matching, slug templating).

### Phase 6 — Hotkeys & lifecycle (1 day)
- `HotkeyManager` (Carbon): default ⌘⇧V overlay, ⌥⇧S shorten, ⌥⇧Q QR, user-remappable in Settings with conflict detection.
- Launch-at-login (SMAppService), "run in background" respawn setting (Paste's App Store behavior), first-run onboarding (permissions walkthrough: Accessibility, API key, hotkeys).

### Phase 7 — Polish, packaging, verification (1–2 days)
- Empty states, toasts, error surfaces (offline, invalid API key, plan limit).
- `xcodebuild -scheme Clipshot test` green; manual pass using `TESTING.md` checklist (copy from 5 apps, paste into 5 apps, fullscreen overlay, permission-denied fallback, auto-shorten rule end-to-end).
- Archive + **notarize** (`xcodebuild -exportArchive` → `notarytool`), or direct DMG; App Store variant deferred (background shorten + global hotkeys are fine there, but review risk on clipboard apps is real — see Risks).

**Total: ~8–12 focused days for a solid v1.**

## 5. Files likely to change (once scaffolded)

```
/Users/ernest/projects/clipboard/Clipshot/
├── Clipshot.xcodeproj
├── Clipshot/
│   ├── ClipshotApp.swift              # entry, MenuBarExtra, scenes
│   ├── Services/ClipboardMonitor.swift
│   ├── Services/HistoryStore.swift    # GRDB schema + FTS5
│   ├── Services/PrivacyFilter.swift
│   ├── Services/PasteEngine.swift
│   ├── Services/BitlyClient.swift
│   ├── Services/BitlyBackend.swift
│   ├── Services/ShortenRulesEngine.swift
│   ├── Services/QRGenerator.swift
│   ├── Services/HotkeyManager.swift
│   ├── UI/OverlayWindow.swift         # NSPanel host
│   ├── UI/TimelineView.swift
│   ├── UI/ItemCard.swift
│   ├── UI/Settings/{GeneralView,PrivacyView,HotkeysView,IntegrationsView}.swift
│   ├── Models/{ClipboardItem,Pinboard,ShortLink,ShortenRule}.swift
│   └── Info.plist
├── ClipshotTests/
│   ├── HistoryStoreTests.swift
│   ├── PrivacyFilterTests.swift
│   ├── BitlyBackendTests.swift
│   └── ShortenRulesEngineTests.swift
├── TESTING.md                         # manual verification checklist
└── .hermes/plans/2026-10-19_164905-paste-shortmenu-hybrid.md
```

## 6. Tests / validation

- Unit: store CRUD + FTS5 search + retention; privacy filter; rules engine pattern/slug logic; Bitly client via `URLProtocol` mocks (200 shorten, 401 `INVALID_ARG_ACCESS_TOKEN`, 404, `BRANDED_LINK_MONTHLY_LIMIT_EXCEEDED`, `DNS_CONFIGURATION_ERROR`, custom keyword via `/bitlinks`, clicks refresh); paste-queue state machine.
- CLI gate: `xcodebuild -scheme Clipshot build` and `xcodebuild -scheme Clipshot test` must pass.
- Manual (`TESTING.md`): copy across ≥5 apps (Safari, Terminal, Finder, Preview, Notes) → all appear in timeline; overlay over full-screen video; paste into rich-text target preserves formatting, plain-paste strips it; Accessibility-denied fallback copies instead of pastes; auto-shorten rule fires exactly once per copy; QR scans with phone camera; pause blocks capture for chosen duration.

## 7. Risks, tradeoffs, open questions

- **Bitly list endpoint is group-scoped**: Recent Links is a local cache of links we created. Click analytics are real (`GET /bitlinks/{bitlink}/clicks`) and stored on cached links. Slugs are immutable after creation.
- **Account dependency**: features require the user's Bitly access token; branded-link limits (`BRANDED_LINK_MONTHLY_LIMIT_EXCEEDED`) and DNS errors must surface cleanly. App must remain useful (full clipboard manager) when the token is absent.
- **Two apps at once**: running alongside real Paste or ShortMenu means double capture / competing hotkeys. Detect and warn.
- **TCC permissions**: Accessibility prompt is friction and App Review risk; overlay-over-fullscreen and status-item behavior need real-device testing (simulator lies).
- **App Store review**: clipboard managers get extra scrutiny (privacy strings, justification). Direct-notarized distribution first, App Store later.
- **Scope trap**: iCloud sync + iOS twin + sharing would double the project. Explicitly out of v1.
- **Naming/legal**: "Paste" and "Short Menu" are trademarks — do not ship the name "Paste" or "ShortMenu" in the bundle/marketing; the app calls the shortening backend "Bitly".

## 8. Open questions (for Ernest before execution)

1. **Distribution**: direct notarized download (fast, no review) vs Mac App Store (reach, but review risk + sandbox constraints on hotkeys/Accessibility)? Recommend direct-first.
2. **Resolved: shortening backend is Bitly API v4.** The user supplies a Bitly access token; `BitlyBackend` is the default provider behind the swappable `ShortenerBackend` protocol so dub or other providers can be added later.
3. **How Paste-like should the overlay be**: faithful bottom-bar timeline, or a conventional Spotlight-style centered palette? Bottom bar is the Paste signature but is the most finicky piece (multi-display, resize, compact mode). Recommend: bottom bar in v1, with palette as a fallback if overlay QA drags.
4. **iCloud sync**: genuinely needed for v1, or Mac-local-only? Recommend local-only for v1.

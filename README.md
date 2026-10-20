# Clipshot

## Development

- `main` receives completed features only — it should always build and pass tests.
- New features go on a branch named `feature/<short-name>` (for example `feature/og-cache-pruning`). Commit the feature there, then merge or open a PR into `main` when it is complete.
- Report the feature branch name when handing off work; do not commit unfinished features directly to `main`.

A native macOS menu-bar clipboard manager with link shortening built in — a Clipshot take on Paste and ShortMenu’s UX. Copy anything: the timeline keeps it, and any URL can be shortened (or auto-shortened) through a swappable shortener backend. The shortening backend is **Bitly API v4**; ShortMenu is only the UX inspiration, not a service dependency.

- Bundle id: `com.ernest.clipshot`
- Deployment target: macOS 14+
- Language: Swift 5 language mode (builds with the Xcode 27 / Swift 6.4 toolchain)
- Storage: SQLite + FTS5 via [GRDB](https://github.com/groue/GRDB.swift) — local only, no iCloud or network sync
- Distribution: direct notarized download (no Mac App Store target, no sandbox)

## Features

**Clipboard history**
- 0.3 s `NSPasteboard.changeCount` polling with SHA-256 dedupe, own-write suppression, pause support
- Captures text, links, rich text, images (PNG on disk), files and colors
- Bottom-bar `NSPanel` timeline on the display under the pointer, over full-screen apps, resizable, compact mode
- Full-text search (FTS5) and filters by type, source app, pinned and pinboard
- Keyboard-first: `←/→`, `↩`, `⇧↩`, `⌘1–9`, `⌘N/E/R/P/K`, `⌘Y` Quick Look, `⌘⌫` delete
- Rich previews: full-content color fills with readable value overlays (hex/rgb/hsl/oklch/oklab/named), Open Graph thumbnails for links, source-app icons and per-app accent-tinted cards
- Plain-text paste, paste stack, Quick Look, pinboards, snippets, edit/rename, retention
- Privacy: bundle-id ignore list (password managers by default), transient/concealed pasteboard markers, timed pause (also suspends OG fetches)

**Link shortening**
- All UI talks to the `ShortenerBackend` protocol (never the REST client)
- `BitlyBackend` default provider: Bitly API v4 at `https://api-ssl.bitly.com/v4`
  - `POST /shorten` for auto slugs (`long_url`, optional `domain`, `group_guid`)
  - `POST /bitlinks` for custom slugs / branded domains (`keyword`, `domain`, `tags`)
  - `PATCH /bitlinks/{bitlink}` for destination/tags; `DELETE /bitlinks/{bitlink}`
  - `GET /bitlinks/{bitlink}/clicks?units=-1&unit=day` for click analytics
- Access token (`Authorization: Bearer …`) stored in the app's own Keychain items (service `com.ernest.clipshot`)
- Custom slug, domain, group GUID, tags, shorten sheet, recent-links menu
- Recent Links shows cached links with click counts; “Refresh Clicks” fetches the all-time timeline
- Declarative auto-shorten rules (URL glob + source app → domain/slug template/auto-copy)
- QR codes via Core Image (`CIQRCodeGenerator`), copy/save as PNG

**Bitly API notes**
- Slugs are immutable: `PATCH /bitlinks/{bitlink}` accepts `long_url` and `tags` only (`capabilities.supportsUpdateSlug == false`).
- `GET /bitlinks` is group-scoped, so Clipshot keeps its own local cache of links it creates; Recent Links is that cache.
- Tags on the auto-slug path are applied with a follow-up PATCH because `POST /shorten` has no tags field.
- Errors surfaced: 401 `INVALID_ARG_ACCESS_TOKEN`, 404, `BRANDED_LINK_MONTHLY_LIMIT_EXCEEDED`, `DNS_CONFIGURATION_ERROR`.

## Build & run

```sh
cd /Users/ernest/projects/clipboard

# Build (ad-hoc signed Debug build)
xcodebuild -scheme Clipshot -configuration Debug build

# Unit tests (hosted in the app target)
xcodebuild -scheme Clipshot -configuration Debug test

# Open in Xcode
open Clipshot.xcodeproj
```

First launch shows onboarding. Grant **System Settings → Privacy & Security → Accessibility** for direct paste; without it Clipshot leaves items on the clipboard instead of synthesizing ⌘V.

Global hotkeys (remappable in Settings): `⌘⇧V` timeline, `⌥⇧S` shorten, `⌥⇧Q` QR.

## Project map

```
Clipshot/
├── App/
│   ├── ClipshotApp.swift        MenuBarExtra + Settings scene + AppDelegate
│   └── AppState.swift           app-wide observable state and actions
├── Models/                      ClipboardItem, Pinboard, ShortLink, ShortenRule, Hotkey
├── Services/
│   ├── ClipboardMonitor.swift   changeCount polling, capture pipeline
│   ├── ClipboardPayloadReader.swift  type sniffing + hashing
│   ├── ClipboardColorParser.swift   hex/rgb/hsl/oklch/oklab/named colors
│   ├── HistoryStore.swift       GRDB migrations, FTS5, pinboards, rules, link cache
│   ├── PrivacyFilter.swift      ignore list, markers, pause window
│   ├── PasteEngine.swift        pasteboard writes, CGEvent ⌘V, paste stack
│   ├── ItemDataStore.swift      image/RTF payload files
│   ├── AppIconProvider.swift    source-app icons + accent extraction
│   ├── OGImageParser.swift      og:image / twitter:image extraction
│   ├── OGImageCache.swift       disk TTL, negative cache, LRU cap
│   ├── OGImageLoader.swift      async page + image fetching
│   ├── LinkPreviewStore.swift   in-flight dedupe + preview state
│   ├── ShortenerBackend.swift   protocol, capabilities, registry
│   ├── BitlyClient.swift        Bitly v4 REST client and DTO mapping
│   ├── BitlyBackend.swift       Bitly provider implementation
│   ├── ShortenRulesEngine.swift glob matching + slug templates
│   ├── HotkeyManager.swift      Carbon RegisterEventHotKey
│   ├── QRGenerator.swift        Core Image QR
│   ├── KeychainStore.swift      backend access tokens
│   ├── AppSettings.swift        UserDefaults-backed settings
│   ├── LaunchAtLogin.swift      SMAppService
│   └── AccessibilityPermission.swift
└── UI/                          overlay panel, timeline, cards, settings, onboarding
```

Tests live in `ClipshotTests/` (HistoryStore, PrivacyFilter, BitlyBackend via URLProtocol, ShortenRulesEngine, PasteStack, ClipboardColorParser, OGImageParser/OGImageCache, AppIconAccent). Manual verification is documented in [TESTING.md](TESTING.md).

## Local data

| Data | Location |
| --- | --- |
| History database (SQLite + FTS5) | `~/Library/Application Support/Clipshot/clipshot.sqlite` |
| Image/RTF payloads | `~/Library/Application Support/Clipshot/Data/` |
| Link preview cache (7-day TTL, 200 MB LRU) | `~/Library/Application Support/Clipshot/OGCache/` |
| Source-app icons and accents | `~/Library/Application Support/Clipshot/AppIcons/` |
| Preferences | `UserDefaults` domain `com.ernest.clipshot` |
| Bitly access token | Keychain, service `com.ernest.clipshot` |

Nothing is uploaded except the link you explicitly shorten (or that a rule shortens) to the configured backend.

## Adding another shortener backend

1. Implement `ShortenerBackend` (`createLink`, `updateLink`, `deleteLink`, `cachedLinks`, `clickStats`, `verifyCredentials`, capabilities).
2. Register it in `ShortenerBackendRegistry` (see `registerBuiltIns()` in `ShortenerBackend.swift`).
3. Point the Settings picker at the new provider id.

The UI only sees the protocol, so no view changes are needed.

## Packaging (Phase 7)

`Scripts/package.sh` archives a Release build (hardened runtime enabled), exports a Developer ID-signed app, optionally notarizes and staples it, and builds a DMG. It requires your own Apple Developer credentials via environment variables — none are included or fabricated in this repo:

```sh
DEVELOPMENT_TEAM=ABCDE12345 \
DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (ABCDE12345)" \
APPLE_ID="you@example.com" \
APPLE_APP_PASSWORD="app-specific-password" \
./Scripts/package.sh
```

Without credentials the script stops before signing/notarization and prints what is missing. The Debug build and test suite do not require a developer account.

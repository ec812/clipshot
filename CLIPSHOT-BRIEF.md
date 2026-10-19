# Task: Build Clipshot — macOS clipboard manager + URL shortener hybrid

Project root: /Users/ernest/projects/clipboard (this is the workspace; put everything here)

Read the full plan first, it is the spec of record:
/Users/ernest/projects/clipboard/.hermes/plans/2026-10-19_164905-paste-shortmenu-hybrid.md

## What to build
A native macOS 14+ app (Swift 5.10, SwiftUI + AppKit where required), working name **Clipshot**, bundle id `com.ernest.clipshot`, that combines Paste (pasteapp.io clipboard manager) with ShortMenu’s menu-bar UX. Shortening is backed directly by **Bitly API v4** (ShortMenu-the-app is a Bitly client; it is the UX inspiration, not a service dependency). Implement the plan's Phase 0 through Phase 7.

## Locked decisions (do not revisit)
- Distribution: direct notarized download. No Mac App Store target, no sandbox entitlements.
- Shortening goes behind a swappable `ShortenerBackend` protocol (createLink / updateLink / deleteLink / clickStats / capabilities + local cache of created links). `BitlyBackend` is the default implementation using Bitly API v4 (`https://api-ssl.bitly.com/v4`, `Authorization: Bearer <token>`). UI must never talk to `BitlyClient` directly — only through the protocol. Leave a registry so other backends (dub, etc.) can be added later.
- Local-first: SQLite via GRDB + FTS5. No iCloud/CloudKit sync, no iOS target in v1.

## Architecture summary (from plan)
- MenuBarExtra status item + NSPanel (.nonactivatingPanel, canJoinAllSpaces, fullScreenAuxiliary) bottom-bar overlay timeline, multi-display aware, compact mode.
- ClipboardMonitor: ~0.3s NSPasteboard.changeCount polling, type sniffing, dedupe by content hash, skip own writes, pause timer.
- HistoryStore (GRDB): items table + FTS5 index + pinboards + short_links cache + shorten_rules tables.
- PasteEngine: CGEvent ⌘V simulation gated on AXIsProcessTrusted(), plain-text variant, paste stack; fallback = copy to clipboard when permission denied.
- PrivacyFilter: bundle-id ignore list, transient content skip, pause with duration.
- HotkeyManager: Carbon RegisterEventHotKey (⌘⇧V overlay, ⌥⇧S shorten, ⌥⇧Q QR), remappable in Settings.
- QRGenerator: CoreImage CIQRCodeGenerator.
- ShortenRulesEngine: rules stored in SQLite, evaluated on copy (url pattern / source app -> domain, slug template, auto-copy).
- Settings scene: General, Privacy, Hotkeys, Integrations (backend picker + API key stored in Keychain).

## Constraints
- Do NOT run any global install scripts, do NOT touch system/keychain outside the app's own Keychain usage in code, do NOT modify anything outside /Users/ernest/projects/clipboard.
- No fabricated results. If `xcodebuild` fails, iterate until it passes or report the exact blocker.
- Do NOT create git commits beyond a local initial commit in this project if you use git at all.
- Tests: unit tests for HistoryStore, PrivacyFilter, BitlyBackend (URLProtocol mock: 200 shorten, 401 `INVALID_ARG_ACCESS_TOKEN`, 404, `BRANDED_LINK_MONTHLY_LIMIT_EXCEEDED`, `DNS_CONFIGURATION_ERROR`, custom keyword via `/bitlinks`, clicks refresh), ShortenRulesEngine. Required gate before claiming done:
  `xcodebuild -scheme Clipshot build` AND `xcodebuild -scheme Clipshot test` must pass.
  If Xcode/CLI tooling is missing, stop and report that instead of pretending.
- Also write TESTING.md with the manual checklist from the plan (copy across ≥5 apps, overlay over full-screen, plain-text paste, permission-denied fallback, auto-shorten rule fires once, QR scans, pause blocks capture).

## Done means
`xcodebuild -scheme Clipshot build` passes, `xcodebuild -scheme Clipshot test` passes, project tree exists under /Users/ernest/projects/clipboard/Clipshot/, TESTING.md present.

Final message must list: files created/changed, exact test output summary (pass/fail counts), build result, and any deviations from the plan with reasons.

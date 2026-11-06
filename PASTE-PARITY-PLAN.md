# Paste Feature Parity Plan — Clipshot

Prepared: 2026-10-21 (HKT) · Baseline: `origin/main` @ `71a7c0f` (PR #2), 225 tests green
Source: Paste changelog (2017 → Sep 2026), pasted as `paste_6_193222.txt`
Rule for tomorrow: NOTHING here is built yet. Plan only. Build per the phases below.

> **STATUS 2026-10-22 EOD: P0 fully shipped — all 7 items merged (PRs #3–#9).**
> Merged main `481c5c3` = origin/main, **326 tests, 0 failures** (225 → 326).
> Completed items are struck through below. Remaining: P1 (#8–#13), P2 (#14–#17),
> Bitly keychain 100002.

---

## Part 1 — Analysis

### What Paste has (grouped from the changelog)

**AI layer (2025–26)**
- *Intelligent Clipboard* (Sep 26): on-device Apple Intelligence model suggests the item
  you're about to paste, using clipboard history + what you're working on.
- *Paste MCP* (Jun 26): built-in **local MCP server** — Claude/Codex/etc. can search
  history, read saved context, create pinboards.
- *Apple Intelligence writing tools* (Nov 25): write from scratch, proofread, rewrite
  inside Paste.

**Search & navigation (2025–26)**
- *Power Search* (Dec 25): smart filters by type/app/date + **OCR text inside screenshots**.
- *Jump to History* (Apr 26): from a search result, jump to the item's original
  location in history/pinboard with surrounding context.
- *Pinboard Filters* (Mar 26): narrow search to one **or multiple** pinboards.

**Privacy (2025)**
- "Show during screen sharing" toggle; ignore confidential content.
  (Paste has had password-manager ignore lists since earlier years.)

**Editing & previews (2020–24)**
- Rich preview (Space / Quick Look) + editing for all content types.
- Cmd+N new text/link items; rename/pin/share from Preview.
- Built-in color picker to adjust copied colors; image rotate; OCR extract;
  edit links in a built-in browser; iPhone document scanning.
- Link previews with OG metadata + thumbnails (2020).
- Paste images as **files** (drag out / file-flavor paste for uploads) (2024).
- Choose which app opens copied files.

**Workflow (2020–24)**
- Paste Stack: paste a set of items in order (2020).
- Advanced Pause Paste with shortcut (2024).
- Multi-select bulk actions; rebuilt resizable window + compact mode (2023).
- Sequential Shift+Cmd+V pinboard navigation (2019).
- Status item single-click opens, ctrl-click menu (2019).

**Platform / product**
- Shortcuts.app + Siri integration (2020–21), widgets, App Intents era features.
- iOS/iPad apps, keyboard extension, sync, shared pinboards, teams, family plan,
  notarization, Liquid Glass design (2025).

### Where Clipshot stands today

| Paste feature | Clipshot implementation | Verdict | Built (PR) |
|---|---|---|---|
| History capture (text/link/image/file/color/RTF, dedupe, retention) | ClipboardMonitor + PayloadReader + HistoryStore | ✅ | ≤ PR #2 |
| Overlay + hotkey ⌘⇧V + menu bar + compact mode | OverlayController, HotkeyManager, MenuBarContent | ✅ | ≤ PR #2 |
| Direct paste (Accessibility), plain paste, clipboard restore | PasteEngine | ✅ | ≤ PR #2 |
| Paste Stack | enqueueForPasteStack / pasteNextInStack | ✅ | ≤ PR #2 |
| Pinboards (create/add/remove/rename/delete, chip filter) | AppState + HistoryStore | ✅ | ≤ PR #2 (rename); PR #7 (multi-board) |
| Link previews (OG thumbnails) | OGImage* + LinkPreviewStore | ✅ | ≤ PR #2 |
| Quick Look preview (Space) | QuickLookPresenter | ✅ | ≤ PR #2 |
| Pause capture | isPaused + PrivacyFilter | ✅ | ≤ PR #2 |
| Ignore password managers / concealed input | PrivacyFilter (1P, Bitwarden, KeePass, concealed, transient) | ✅ | ≤ PR #2 |
| Item edit + rename | Sheets/EditorRequest + previewTitle | ✅ | ≤ PR #2 |
| Link previews, QR, Bitly short links | QRGenerator, BitlyBackend | ✅ (Bitly goes beyond Paste) | ≤ PR #2 |
| Code detection + syntax highlighting | CodeDetector/Highlighter/Store | ✅ (beyond Paste) | ≤ PR #2 |
| Color cards (hex/rgb/hsl/oklch/cmyk/bare-hex) | ClipboardColorParser | ✅ (beyond Paste) | ≤ PR #2 |
| Image thumbnails (files + pathnames, aspect-correct) | ClipImageStore + previewImagePath | ✅ | ≤ PR #2 |
| ~~Multi-pinboard search filter~~ | `filterPinboardIDs: Set<Int64>` + SQL `IN` | ✅ | PR #7 |
| ~~Power Search (type/app/date syntax, OCR in images)~~ | SearchQueryParser + OCR text searchable | ✅ | PR #3, PR #4 |
| ~~Jump to History~~ | `AppState.reveal(_:)` | ✅ | PR #5 |
| ~~Paste MCP~~ | loopback HTTP JSON-RPC, 6 tools, token | ✅ | PR #6 |
| Intelligent Clipboard | — | ❌ | — |
| Apple Intelligence writing tools | — | ❌ | — |
| Screen-sharing / recording privacy | — | ❌ | — |
| ~~New item Cmd+N~~ | ⌘N text + ⌘⇧N link + menu entries | ✅ | PR #8 |
| ~~Paste/drag images as files~~ | drag-out (file URL + bitmap) + Paste as File | ✅ | PR #9 |
| Multi-select bulk actions | — | ❌ | — |
| Image rotate / color picker edit | — | ❌ | — |
| Shortcuts / App Intents | none in codebase | ❌ | — |
| iOS, sync, shared pinboards, teams, family, widgets | — | 🚫 out of scope (see non-goals) | — |

*Built (PR): which PR shipped the Paste feature. `≤ PR #2` = existed at the plan
baseline 2026-10-21 (`71a7c0f`); `PR #3–#9` = shipped during the 2026-10-22 P0
push; `—` = not built yet.*

### Our differentiators to protect (things Paste doesn't do)
- Syntax highlighting of copied code + per-item override
- Multi-format color cards incl. CMYK/oklch with legacy-row recovery
- Bitly short links + custom shorten rules
- Pasteboard-restore-after-paste (privacy)
- Aggressive secret hygiene (concealed input + password-manager ignores)

---

## Part 2 — The build plan

### P0 — tomorrow (high value, tractable, local-first) — ✅ ALL COMPLETE 2026-10-22

**~~1. Paste MCP parity — local MCP server~~ ✅ shipped (PR #6, `46de211`, 2026-10-22)** · L · flagship gap
- What: loopback HTTP JSON-RPC server in-app implementing MCP
  (`initialize`, `tools/list`, `tools/call`) so Claude/Hermes/Codex can query
  the clipboard history. Off by default; Settings toggle shows the URL + token.
- Where: new `Services/MCPServer.swift` (NWListener on 127.0.0.1, random port,
  bearer token); read paths via HistoryStore; toggle in AppSettings;
  AppState lifecycle (start/stop with app).
- v1 tools: `search_history(query, kind?, limit?)`, `get_item(id)`,
  `list_pinboards`, `get_pinboard_items(name)`, `create_pinboard(name)`,
  `add_item_to_pinboard(item_id, pinboard)`.
- Security: loopback-only + token + no writes outside pinboards; state in report.
- Acceptance: Hermes/Claude config connects; all tools return real data;
  unit tests for the JSON-RPC framing; suite stays green.

**~~2. Power Search~~ ✅ shipped (PR #3, `7b76932`)** · M
- Query syntax: `kind:image`, `from:"Safari"`, `date:7d|today|…`,
  `pinboard:Remote`, `text:"…"`, free text default. Parse into a struct;
  feed AppState.reload's existing filter chain.
- Where: new `Services/SearchQueryParser.swift` (pure, fully unit-tested);
  AppState filter fields; TimelineView chips unchanged (syntax + chips compose).
- Acceptance: parser table-tests; store-level filter tests; chips + syntax
  don't fight (last-writer-wins documented).

**~~3. OCR for images (text recognition)~~ ✅ shipped (PR #4, `e1a8542`)** · M
- Vision `VNRecognizeTextRequest`, **never on the capture hot path**:
  context menu "Extract Text" on demand + optional background indexing of
  recent image items (toggle). Persist `ocrText` (new column → migration via
  existing `migrateIfNeeded`; mind sqlite-migration-patterns pitfalls).
- Where: new `Services/OCREngine.swift`; HistoryStore migration + column;
  ItemCard context menu; search includes ocrText.
- Acceptance: screenshot-with-text fixture → extracted text searchable;
  capture latency unaffected (test: process() does no Vision work).

**~~4. Jump to History~~ ✅ shipped (PR #5, `c2fecf2`)** · S
- From a search result's context menu: clear search, reset filters to the
  item's board context, select item, scroll to center (selection scroll
  exists) with surrounding context visible.
- Where: AppState (reveal(item:)), ItemCard/TimelineView context menu.
- Acceptance: search → jump → item centered, no query left active.

**~~5. Multi-pinboard search filter~~ ✅ shipped (PR #7, `d1ee1f8`)** · S
- `filterPinboardIDs: Set<Int64>` (replace single), chips multi-select
  (toggle), SQL `IN` query.
- Where: AppState, HistoryStore.items query, TimelineView chips.
- Acceptance: two boards selected → union; deselect empty → all.

**~~6. Manual new items (⌘N)~~ ✅ shipped (PR #8, `eb99830`)** · S
- New Text Item / New Link Item sheets (reuse the existing editor request),
  persisted like captures (kind text/url, own sourceApp "Clipshot").
- Where: AppState.beginNewItem, Sheets, TimelineView shortcut, menu.
- Acceptance: create → appears at timeline head → paste works.

**~~7. Paste/drag images as files~~ ✅ shipped (PR #9, `481c5c3`)** · M
- Drag-out: NSItemProvider with file URL (temp copy) + bitmap from timeline
  cards; alt-paste action "Paste as File" writing `public.file-url`.
- Where: TimelineView .draggable/NSItemProvider, PasteEngine kind-agnostic
  file-flavor path (already exists for .file), temp-file lifecycle in
  ItemDataStore (mind the retention/orphan findings).
- Acceptance: drag an image card into a browser upload picker → works.

### P1 — right after
**8.** Screen-sharing/recording privacy — spike first (honest: no clean public API;
options: CGWindowList sharing-state polling, ScreenCaptureKit prompts, TCC-based
heuristics); ship a Settings toggle only if the spike proves reliable. · M-spike
**9.** Multi-select bulk actions (shift/⌘ click → delete/pin/to-pinboard). · M
**10.** Apple Intelligence writing tools (proofread/rewrite/polish on selected
text in editor + context menu) — FoundationModels / Writing Tools API on the
user's OS; hide when unavailable. · M-spike
**11.** Image rotate + color-picker edit for color items. · S
**12.** App Intents: search history, get latest item, create pinboard. · S
**13.** Status-item ctrl-click polish + sequential pinboard navigation shortcut. · S

### P2 — later / experimental
**14.** Intelligent Clipboard — heuristic MVP first (recency × frontmost-app
affinity ranking surfaced as "Suggested" chip); FoundationModels reranker later. · L
**15.** Liquid Glass visual pass (macOS 26 materials) — with design taste, not a rewrite. · M
**16.** Notarization + update channel (distribution hygiene). · M
**17.** "Choose app to open copied files" setting. · S

### Non-goals (🚫, with rationale)
- iOS/iPad app, widgets, keyboard extension — different product, years of work.
- iCloud sync, shared pinboards, teams, family billing — Paste's business; we are
  a local-first single-user app. (History DB is already a plain SQLite file — if
  sync ever matters, syncthing/iCloud Drive folder sync is the cheap path.)
- Notarization is P2 because it's release plumbing, not a user-facing feature.

---

## Part 3 — Open questions for Ernest (answer before building) — resolved 2026-10-22
1. ~~**MCP transport**: loopback HTTP + token (recommended — works with Hermes native
   MCP client and Claude Desktop config) vs stdio bridge process?~~ → **loopback HTTP + bearer token** (shipped).
2. ~~**MCP write scope**: read-only tools first (recommended) or include
   create-pinboard/add-to-pinboard in v1?~~ → **pinboard writes included** — the only writes, no delete/item mutation.
3. ~~**OCR**: on-demand only (recommended) or also background-index recent images?~~ → **on-demand only**; background indexing deferred.
4. ~~**P0 scope**: build all 7, or 1–5 core and park 6–7? (recommend all — they're
   sized for one day + follow-ups)~~ → **all 7 built and merged same day.**
5. **Writing tools (P1-10)**: worth a spike tomorrow, or park it?
6. Reminder: **Bitly keychain error 100002 is still open** — brief ready at
   `CLIPSHOT-KEYCHAIN-BRIEF.md`. Slot it in as day-one first task or after P0?

## Part 4 — Build discipline (tomorrow)
- One branch per P0 item off main; PR per item; serial cmd sessions (never two on
  one worktree). Feature branches: `feature/mcp-server`, `feature/power-search`,
  `feature/ocr`, …
- Gate every PR: filtered build grep prints nothing + full suite green (225
  baseline + new tests) + red→green for anything bug-shaped + PNG evidence for UI.
- New pure logic (query parser, MCP framing, OCR decisioning) goes in
  dependency-injected service types with table-driven tests — view code stays thin.
- Migrations: one place (`migrateIfNeeded`), additive-only columns, tested both
  directions per sqlite-migration-patterns.
- Manual checks listed in every handoff; renders to /tmp for eyeballing.

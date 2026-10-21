# Clipshot Code Highlighting — Design

Date: 2026-10-21
Status: approved for implementation planning
Scope: `.text` card previews only

## Goal

Detect when copied text is actually code and render that card's preview with syntax highlighting. Prose, emails, and every non-`.text` item keep today's rendering. Detection is automatic, lazy, and bounded so the clipboard capture path is untouched.

The design companion settled the open questions:

- Control: automatic detection plus a per-item override.
- Timing: lazy at first render, off-main, memory-cached by `item.hash`; no database migration.
- Languages: Swift, JavaScript/TypeScript, Python, JSON, shell, SQL, HTML, CSS, C-family, plus a generic fallback.
- Rendering: native SwiftUI `AttributedString` + `Text`; no new dependency.
- Surface: card preview only; Quick Look, editor, and menus are unchanged.
- False positives: conservative thresholds; the override is the escape hatch.

## Detection

- Input is `item.text` and only `kind == .text`; `.rtf` keeps its current preview.
- Bound the scan to the first **16,384 characters**. Character scanning only; no heavy regex. Runs off-main and is cached.
- Languages: `swift`, `javascript` (includes TypeScript), `python`, `json`, `shell`, `sql`, `html`, `css`, `cLike`, `generic`.
- Strong shortcuts:
  - `JSONSerialization` succeeds on a trimmed `{`/`[` payload → `json`.
  - `#!` shebang → shell or Python (by interpreter).
  - `<!DOCTYPE`, `<html`, or paired tags → `html`.
  - SQL keyword sequence (`SELECT … FROM`, `INSERT INTO`, `CREATE TABLE`) → `sql`.
- Language signals:
  - Swift: `import`, `func`, `let`/`var`, `guard`, `class`/`struct`/`enum`/`protocol`, `@MainActor`, `->`.
  - JS/TS: `function`, `=>`, `const`, `console.log`, `require(`, `import … from`, `interface`, `type`.
  - Python: `def`, `from … import`, `self.`, `print(`, `#` comments, colon-terminated blocks.
  - Shell: shebang, command-leading `sudo`/`cd`/`echo`/`export`, flags.
  - SQL: `SELECT`/`FROM`/`WHERE`/`INSERT`/`UPDATE`/`CREATE`.
  - C-family: `#include`, `public static`, `fmt.`, `fn `, `package `, braces/semicolons.
  - HTML/CSS: tags, selectors, `{ property: value; }`.
- Generic code score: multiple lines, indentation, brace/bracket/semicolon density, average line length, comments/strings present, symbol-to-word ratio.
- Negative prose score: English stopword ratio, sentence punctuation at line ends, very low symbol density, email/URL shapes.
- Decision: require a minimum generic code score plus a winning language signal; otherwise return `nil`. Use `generic` only when code-like but no language wins. Never highlight single words, IDs, dates, or emails.

## Highlighting

- Display bound: at most **2,000 characters or 40 lines**, cut at a line boundary. Tabs normalized to four spaces. Original newlines and indentation are preserved.
- Generic scanner emits tokens: `keyword`, `type`, `string`, `number`, `comment`, `plain`.
- Per-language line-comment prefixes, block-comment pairs, string delimiters (including Python triple quotes and JS backticks), and keyword/type sets.
- Unterminated strings/comments consume safely to the end of the bounded prefix.
- `CodeTheme` (light + dark) colors keywords, strings, comments, numbers, and types; all other text stays `Color.primary` and blends with the card.
- Code preview typography: system monospaced font, **11.5 pt compact / 12.5 pt full**, same 4/7-line limits, frame, padding, and `.textSelection(.disabled)` as the current text preview.
- Attributed runs override color only; the view supplies the base font.

## Store, cache, and override

- New `CodeHighlightStore`, modeled on `ClipImageStore`:
  - `@Published private(set) var revision = 0`.
  - Results cached by `item.hash`: `.plain`, `.code(language, light, dark)`, or in-flight.
  - `attributedPreview(for:colorScheme:)` returns the cached string, starts one detached `.utility` detection per hash, and bumps `revision` when done.
  - Detection and both color-scheme variants are built off-main and cached, so `body` does only a lookup.
- Per-item override stored in `UserDefaults` keyed by hash (small, pruned dictionary). Override wins over detection. Forced code with no detected language uses `generic`.
- Context menu (`.text` only): "Highlight as Code" / "Show as Plain Text" according to the effective state.

## View integration

- `AppState` owns `let codeHighlight = CodeHighlightStore()`, passed through `TimelineView` into `ItemCard` alongside `clipImages` / `linkPreviews`.
- `ItemCard.preview` gains an explicit `case .text:` before `default:`:
  - highlighted code → `Text(attributed)` with the code typography;
  - pending or plain → today's exact `Text(item.previewText)` rendering.
- Processing starts in `onAppear` (like `clipImages.ensureLoaded`); the first frame may be plain for a few milliseconds.
- `.rtf`, `.url`, `.image`, `.file`, and `.color` are untouched.

## Structure

New files:

- `Clipshot/Services/CodeDetector.swift` — `CodeLanguage` and the detection heuristic.
- `Clipshot/UI/CodeHighlighter.swift` — tokenizer, `CodeTheme`, attributed-string builder.
- `Clipshot/Services/CodeHighlightStore.swift` — cache, async processing, overrides.
- `ClipshotTests/CodeDetectorTests.swift`
- `ClipshotTests/CodeHighlighterTests.swift`
- `ClipshotTests/CodeHighlightStoreTests.swift`

Files touched:

- `Clipshot/App/AppState.swift` (own the store)
- `Clipshot/UI/TimelineView.swift` (pass the store)
- `Clipshot/UI/ItemCard.swift` (store property, `.text` branch, `onAppear`, override menu)
- `Clipshot.xcodeproj/project.pbxproj` (three app and three test files; four entries each)
- `TESTING.md`, `README.md`
- `Docs/verify-code-highlight.png`

## Testing and verification

Automated:

- `CodeDetectorTests`
  - positive: Swift, JS/TS, Python, JSON object+array, shell script, SQL, HTML, CSS, C-like, indented multi-line code.
  - negative: prose paragraph, email, prose with dashes/parentheses, single word, dates/IDs, URL-plus-prose, one-line natural language.
  - edge: empty/whitespace, CRLF, >16 KB prefix, minified JSON, JSON-like prose.
- `CodeHighlighterTests`
  - token kinds for keywords/strings/comments/numbers per representative language.
  - unterminated strings/comments; tabs; text preservation; max-char/line bounds.
  - light vs dark theme color selection.
- `CodeHighlightStoreTests`
  - one detection per hash; plain and code results cached; one revision bump.
  - override wins over detection, including forced `generic`.
  - pending returns plain.
- Existing 152 tests remain green; new tests are additive.
- Gate: filtered `xcodebuild` warning/error grep, full `xcodebuild test`.

Manual:

- Copy real snippets from Xcode/VS Code/Python/JSON/shell/SQL/HTML/CSS → highlighted card, line breaks preserved, 4/7-line limits respected.
- Copy prose, an email, and dashed prose → no highlighting.
- Override both directions; verify it survives relaunch.
- Compact and full overlay; light and dark.
- Capture remains responsive.

## Non-goals

- Quick Look, editor sheet, search results, and menus.
- Persisting detection results or language-based filtering (future migration).
- Grammar-accurate highlighting for every language; `generic` is a fallback.
- Detecting code inside `.rtf`, `.url`, `.file`, or `.image` items.

## Risks and mitigations

- **False positives** → conservative thresholds, negative tests, and the override.
- **Render cost** → bounded prefixes, off-main tokenization, per-(hash, scheme) cache; `body` does only a lookup.
- **`.rtf` regression** → explicit `.text` case; `default:` unchanged.
- **Layout** → preserve line limits and frame; only the code path changes font.
- **Hand-maintained Xcode project** → register all six new files in the four required `project.pbxproj` sections and lint with `plutil`.
- **Memory growth** → one bounded cache entry per hash; overrides pruned.

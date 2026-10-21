# Code Highlighting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect code-like `.text` clipboard items and render their card preview with native SwiftUI syntax highlighting, with a per-item override and no capture-path work.

**Architecture:** Pure `CodeDetector` (bounded heuristic) + `CodeHighlighter` (generic tokenizer and `AttributedString`) + `CodeHighlightStore` (lazy off-main cache keyed by `item.hash`, UserDefaults override). `ItemCard` gains an explicit `.text` branch and a context-menu override; all other kinds are untouched.

**Tech Stack:** Swift 5 language mode, SwiftUI, AppKit, XCTest, macOS 14 deployment target, GRDB (unchanged), hand-maintained `Clipshot.xcodeproj/project.pbxproj`.

**Branch:** `feature/code-highlight`, created from `main` after the design spec commit.

---

## File Structure

**Create**

- `Clipshot/Services/CodeDetector.swift` — `CodeLanguage` and bounded detection heuristic.
- `Clipshot/UI/CodeHighlighter.swift` — tokenizer, `CodeTheme`, attributed preview builder.
- `Clipshot/Services/CodeHighlightStore.swift` — lazy cache, async processing, overrides.
- `ClipshotTests/CodeDetectorTests.swift`
- `ClipshotTests/CodeHighlighterTests.swift`
- `ClipshotTests/CodeHighlightStoreTests.swift`

**Modify**

- `Clipshot/App/AppState.swift` — own `CodeHighlightStore`.
- `Clipshot/UI/TimelineView.swift` — pass the store into `ItemCard`.
- `Clipshot/UI/ItemCard.swift` — store property, `.text` preview branch, `onAppear`, override menu.
- `Clipshot.xcodeproj/project.pbxproj` — register six new files.
- `TESTING.md`, `README.md`, `Docs/verify-code-highlight.png`.

**Unchanged**

- Capture pipeline, database schema, `ClipboardItem`, Quick Look, editor, menus, all non-`.text` previews.

---

## Task 1: Detector

**Files:**
- Create: `Clipshot/Services/CodeDetector.swift`
- Create: `ClipshotTests/CodeDetectorTests.swift`
- Modify: `Clipshot.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing detector tests**

Cover positives for Swift, JS/TS, Python, JSON object/array, shell, SQL, HTML, CSS, C-like, indented multi-line code; negatives for prose, email, prose with dashes/parentheses, single words, dates/IDs, URL-plus-prose; edge cases for empty, whitespace, CRLF, >16 KB input, minified JSON, JSON-like prose.

Expected API:

```swift
enum CodeLanguage: String, CaseIterable {
    case swift, javascript, python, json, shell, sql, html, css, cLike, generic
}

struct CodeDetector {
    static let maxDetectionCharacters = 16_384
    static func detect(_ text: String) -> CodeLanguage?
}
```

- [ ] **Step 2: Implement the heuristic**

Scan only `text.prefix(maxDetectionCharacters)`; no heavy regex; no UI or AppKit dependencies. Implement JSON/shebang/HTML/SQL shortcuts, per-language signal sets, generic code scoring, prose scoring, and the conservative threshold.

- [ ] **Step 3: Run detector tests, then wire the files**

Register `CodeDetector.swift` and `CodeDetectorTests.swift` in the four pbxproj sections (build file, file reference, group, sources phase), then:

```bash
xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug test \
  -only-testing:ClipshotTests/CodeDetectorTests
```

Expected: all detector tests pass.

---

## Task 2: Highlighter

**Files:**
- Create: `Clipshot/UI/CodeHighlighter.swift`
- Create: `ClipshotTests/CodeHighlighterTests.swift`
- Modify: `Clipshot.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing highlighter tests**

Assert token kinds for keywords, types, strings, comments, and numbers in representative Swift/JS/Python/JSON/SQL snippets; unterminated strings/comments; tab normalization; text preservation; 2,000-char/40-line bound; light/dark theme colors.

Expected API:

```swift
enum HighlightTokenKind { case keyword, type, string, number, comment, plain }

struct CodeTheme {
    static func colors(for colorScheme: ColorScheme) -> Colors
}

struct CodeHighlighter {
    static let maxPreviewCharacters = 2_000
    static let maxPreviewLines = 40
    static func attributedPreview(
        _ text: String,
        language: CodeLanguage,
        colorScheme: ColorScheme
    ) -> AttributedString
}
```

- [ ] **Step 2: Implement the tokenizer and theme**

Generic scanner with per-language comment/string/keyword tables. Normalize tabs to four spaces. Preserve newlines and indentation. Apply `.foregroundColor` runs; leave `plain` unset so `Color.primary` shows through. Bound work before scanning.

- [ ] **Step 3: Run highlighter tests and register the files**

```bash
xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug test \
  -only-testing:ClipshotTests/CodeHighlighterTests
```

Expected: all highlighter tests pass.

---

## Task 3: Store and overrides

**Files:**
- Create: `Clipshot/Services/CodeHighlightStore.swift`
- Create: `ClipshotTests/CodeHighlightStoreTests.swift`
- Modify: `Clipshot.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing store tests**

Assert one detection per hash, plain and code caching, one revision bump, override precedence, forced `generic` when detection is nil, and pending → plain. Inject a detector and highlighter into the store so tests can count calls without sleeping.

Expected API:

```swift
@MainActor
final class CodeHighlightStore: ObservableObject {
    @Published private(set) var revision = 0
    func attributedPreview(
        for item: ClipboardItem,
        colorScheme: ColorScheme
    ) -> AttributedString?
    func isCode(for item: ClipboardItem) -> Bool
    func setOverride(_ value: Bool?, for item: ClipboardItem)
}
```

- [ ] **Step 2: Implement the store**

Memoize by `item.hash`; track in-flight hashes; run detection and both color-scheme attributed variants on `Task.detached(priority: .utility)`; store on the main actor and bump `revision`. Persist overrides in a small UserDefaults dictionary keyed by hash; default nil. Force code uses the detected language or `.generic`.

- [ ] **Step 3: Run store tests and register the files**

```bash
xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug test \
  -only-testing:ClipshotTests/CodeHighlightStoreTests
```

Expected: all store tests pass.

---

## Task 4: View integration and override UI

**Files:**
- Modify: `Clipshot/App/AppState.swift`
- Modify: `Clipshot/UI/TimelineView.swift`
- Modify: `Clipshot/UI/ItemCard.swift`

- [ ] **Step 1: Own and pass the store**

Add `let codeHighlight = CodeHighlightStore()` in `AppState` beside `clipImages`/`linkPreviews`. Pass it into `ItemCard` from `TimelineView` in the existing initializer.

- [ ] **Step 2: Add the `.text` preview branch**

In `ItemCard.preview`, add `case .text:` before `default:`:

- If `codeHighlight.attributedPreview(for: item, colorScheme: colorScheme)` is non-nil:
  `Text(attributed)`, monospaced, 11.5/12.5 pt, line limit 4/7, same frame and `.textSelection(.disabled)`.
- Otherwise: today's `Text(item.previewText)`, 13/14.5 pt, line limit 4/7.

Leave `default:` (`.rtf`) and all other cases untouched.

- [ ] **Step 3: Kick processing and add the override**

In `onAppear`, call the store for `.text` items. In `contextMenu`, for `.text` only, add either “Highlight as Code” or “Show as Plain Text” based on `isCode(for:)`, calling `setOverride`.

- [ ] **Step 4: Build and run the full suite**

```bash
xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug build 2>&1 \
  | grep -E "(warning|error)" | grep -iE "itemcard|codehigh"
xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug test 2>&1 | tail -5
```

Expected: the filtered grep prints nothing; `** TEST SUCCEEDED **` with 152 + new tests.

---

## Task 5: Documentation and verification

**Files:**
- Modify: `TESTING.md`
- Modify: `README.md`
- Create: `Docs/verify-code-highlight.png`

- [ ] **Step 1: Update TESTING.md**

Add the new test classes/counts, automated coverage rows, and a manual checklist section covering code/prose/override/compact/dark-mode/capture responsiveness. Reference the verification capture.

- [ ] **Step 2: Update README.md**

Add the code-highlighting feature bullet and new Service/UI entries to the project map.

- [ ] **Step 3: Capture verification evidence**

Render or screenshot the overlay with a highlighted code card and a plain prose card; save as `Docs/verify-code-highlight.png`.

- [ ] **Step 4: Final verification**

```bash
xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug build 2>&1 \
  | grep -E "(warning|error)" | grep -iE "itemcard|codehigh|pbxproj"
xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug test 2>&1 | tail -5
plutil -lint Clipshot.xcodeproj/project.pbxproj
git status --short
```

Expected: no filtered diagnostics, `** TEST SUCCEEDED **`, `project.pbxproj: OK`, and only intended files changed.

---

## Final acceptance checklist

- [ ] Code-like `.text` items highlight; prose/email/dashed prose do not.
- [ ] `.rtf` and all other preview kinds are unchanged.
- [ ] Override both directions works and persists.
- [ ] Compact and full, light and dark layouts are correct.
- [ ] Capture path has no new work.
- [ ] Existing 152 tests plus new tests pass with zero failures.
- [ ] No compiler warnings in touched files.
- [ ] Design spec and implementation plan are committed.

# Bug: "the copy glyph in the card is paste, not copy"

Project root: /Users/ernest/projects/clipboard (this IS the working directory)
Branch: feature/horizontal-scroll (has the new horizontal-scroll work + main).

## User report

Verbatim: "the copy glyph in the card is paste, not copy" — clicking the
copy glyph (the first footer icon in an ItemCard) in the card performs
PASTE, not copy. (Secondary possibility: the glyph itself visually reads
as the paste icon — verify which is actually true before fixing.)

## What I already ruled out (static tracing — all correct in source)

- `CardChrome.swift:205`: `iconButton("doc.on.doc", help: "Copy item", action: onCopy)` — first button is copy, glyph name is the copy symbol.
- `ItemCard.swift:67-68` passes onCopy/onPaste unlabeled-swapped? No — labels correct.
- `TimelineView.swift:341-342`: `onPaste: { appState.paste(item) }`, `onCopy: { appState.copy(item) }` — correct.
- `AppState.copy()` (line 352) → `pasteEngine.copyToClipboard()` (PasteEngine:83) — writes pasteboard + toast only; `simulateCommandV()` is only called inside `paste()`.
- Context menu order (ItemCard:231-233): Paste, Paste as Plain, Copy — correct labels.

So the static mapping is right. The bug is RUNTIME.

## Prime suspect #1 — the horizontal-scroll adapter we just added

`HorizontalScrollWheel.swift` (new on this branch) is attached as
`.background(HorizontalScrollWheelAdapter())` to BOTH scroll views
(TimelineView:293 filter bar, :363 timeline). A background
`NSViewRepresentable` hosts a real NSView; if its `hitTest` isn't
suppressed it can intercept/alter mouse routing for everything above it —
including footer button taps. The user reported this immediately after
testing the horizontal-scroll build. Check whether the tap that reaches
the card hits the paste action or falls through to the card's
`.onTapGesture(count: 2) { onPaste() }` (ItemCard:89).

## Other hypotheses to discriminate between

1. Tap on copy button falls through / is misrouted → card double-tap
   gesture (`onTapGesture(count: 2) → onPaste`) or another gesture wins.
2. Button hit area offset from the rendered glyph (padding/overlay
   mismatch) so the visible copy glyph's point lands on the paste button.
3. The glyph LOOKS like paste to the user (visual-only; action is fine) —
   e.g. doc.on.doc rendering unexpectedly at the size/weight used.
4. Stale app build (user ran an older binary than this branch).

## Required approach: reproduce FIRST, then fix

- Instrument the LIVE path before changing anything: verify which action
  actually fires when the copy glyph is clicked. A workable harness: host
  the card in an `NSHostingView` in a unit test and synthesize mouse
  events at the copy button's coordinates (get the button frame via
  accessibility or geometry), asserting onCopy fires and onPaste does not.
  If synthesizing clicks is impractical, add temporary logging to
  CardFooter/FooterIconButton actions + the card tap gestures, and reason
  from what's reachable.
- Do NOT re-assert the static wiring as proof it works — I already did
  that. Verify, don't re-assert.
- Fix only the discriminated root cause. If it turns out to be the
  adapter's hit-testing, fix the adapter (e.g. NSViewRepresentable
  hitTest → nil / allowsHitTesting) WITHOUT breaking the horizontal
  scrolling feature — the hscroll feature must still work after your fix.

## Constraints

- Keep the horizontal-scroll feature fully working (both vertical-wheel
  remap and native horizontal input).
- No global NSEvent swizzling.
- Don't touch unrelated code.

## Verification before claiming done

- `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug build 2>&1 | grep -E "(warning|error)" | grep -iE "itemcard|cardchrome|horizontalscroll"` → nothing.
- `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug test 2>&1 | tail -5` → `** TEST SUCCEEDED **`, 150+ tests, 0 failures.
- If your repro test exists, show its name and result — the test must FAIL
  against the buggy behaviour (red) and PASS after the fix (green).
  If you genuinely cannot reproduce, say so plainly, state what you proved
  instead, and list what manual check the user should do.

## Handoff

Bugfix → commit on the current branch (feature/horizontal-scroll), message
stating the REAL root cause. Report: root cause, files changed, test
evidence (red→green if applicable), any remaining manual checks.

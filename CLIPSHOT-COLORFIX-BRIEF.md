# Bug: color cards render as plain Text + format coverage (CMYK etc.)

Project root: /Users/ernest/projects/clipboard (this IS the working directory)
Repo is on `main` (HEAD = 99f9ef9). Create `feature/color-cards` when you implement.

## User report (verbatim)

"The color cards broke, it is only showing a hex value now and showing as
Text. Make sure HEX, RGBA, RGB, CMYK, HSL, etc are shown as color cards."

## What my git diff already established (binding prior work — don't re-derive)

- `git log -- ClipboardColorParser/ClipboardPayloadReader`: classifier and
  parser untouched since the restyle merge. Parser passes 20/20 tests
  TODAY (hex 3/4/6/8, rgb/rgba comma+space+percent, hsl/hsla, oklch,
  oklch/oklab, named, rejects mixed content).
- Current ItemCard `case .color` branch (on disk) is intact: full-bleed
  `Rectangle().fill(parsed)` + overlaid `Text(text)` — reads correctly,
  so the break is RUNTIME: either `item.kind` is not `.color` when it
  should be, or the branch's `ClipboardColorParser.parse(item.text)`
  returns nil and it falls to `fallbackPreview` (plain Text).
- Recent commits touching preview routing: `99f9ef9` (code highlight —
  added explicit `case .text`, CodeDetector/Store; did NOT touch
  `.color`; runs `codeHighlight.ensureProcessed(item)` in onAppear for
  every card) and restyle `0e776d3` (rewrote the card layout/color
  overlay).
- CMYK: zero occurrences anywhere in Clipshot/ or ClipshotTests/ —
  `cmyk()` was never supported. This is a genuine feature gap, not a
  regression, but the user now requires it.

## Prime suspects to discriminate at runtime (in order)

1. **RTF-flavor precedence in ClipboardPayloadReader** (~line 93): the
   `snapshot.rtfData` branch runs BEFORE color classification — hex or
   rgb() copied from a rich source (browser devtools, Figma, Xcode) with
   an RTF flavor lands as kind `.rtf`/`.text` → renders as plain Text.
2. A pasteboard carries NSColor colorData but the string flavor differs
   (or vice versa) — trace which branch actually wins for real copies.
3. `CodeHighlightStore` / the new `.text` branch catching color-ish
   strings (e.g. short hex like `FF5733` without `#`, or `0x…`) — those
   classify as `.text` and may now show as highlighted monospaced code.
4. Anything you find with instrumentation — verify, don't assume.

## Required approach: reproduce FIRST

Build a classification-level repro BEFORE fixing: drive
`ClipboardPayloadReader`'s capture with synthetic NSPasteboard snapshots
(or a real pasteboard) for a matrix of inputs × flavor combinations:
- inputs: `#FF0000`, `#f00`, `rgba(30,144,255,0.6)`, `rgb(1 2 3 / 80%)`,
  `hsl(120,60%,50%)`, `cmyk(0,100,100,0)`, `FF5733` (no hash)
- flavors: string-only; string+RTF; NSColor colorData; string+RTF+color
Determine which cells produce kind `.color` today vs what the user
expects. Red test = a case the user expects to be a color card that
comes out as text. Then fix ONLY the discriminated cause.

## Fix requirements

1. Root cause of the Text-instead-of-color regression (from step above).
2. ALL of these must classify AND render as color cards:
   HEX (with/without #? — decide and state), RGBA, RGB, HSL, **CMYK**
   (add `cmyk()`/`cmyka()` parsing to ClipboardColorParser → NSColor,
   percentage + 0-100 or 0-1 semantics: pick one, document it, test it).
   Keep oklch/oklab/named working.
3. False-positive guard: prose must never become a color card
   (`testRejectsMixedContent`-style cases stay green; add for CMYK).
4. Don't break the code-highlight feature (197 tests must stay green) —
   if fix touches shared preview routing, keep `.text`/code behavior for
   genuine code.

## Verification gate (run yourself, quote your own output)

1. `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug build 2>&1 | grep -E "(warning|error)" | grep -iE "clipboardcolor|payloadreader|itemcard"` → nothing.
2. `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug test 2>&1 | tail -5` → `** TEST SUCCEEDED **`, 197 existing + your new tests, 0 failures.
3. Offscreen render evidence: host real ItemCards for the fixed inputs
   (both color schemes, normal + compact), save PNG(s) to /tmp/, state
   exactly what they show.

## Handoff

Bugfix + feature → branch `feature/color-cards`, commit with the REAL
root cause in the message. Report: root cause (with the red→green
evidence), files changed, your own build/test output, PNG paths, any
deviations, and what manual check remains for the user.

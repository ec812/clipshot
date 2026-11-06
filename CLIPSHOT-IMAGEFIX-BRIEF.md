# Bug: copying an image shows its path instead of the image

Project root: /Users/ernest/projects/clipboard (this IS the working directory)
Current HEAD: 2cfabfb on `feature/color-cards`. Create `feature/image-preview`
BRANCHED FROM THIS HEAD — your ClipboardPayloadReaderTests harness from the
color fix is needed for the repro, so do not branch from main.

## User report (verbatim)

"when I copy an image, is only showing its path, it should show the image"

## What I already traced (binding — don't re-derive)

- ItemCard `.image` preview (line ~197) renders correctly via
  ClipImageStore when kind == .image and dataPath loads. `.file` preview
  (~line 209) is doc.fill + Text(title ?? previewText) — it NEVER renders
  an image, and `fallbackPreview` is Text.
- ClipboardPayloadReader.process order: FILE branch (fileURLs) runs
  BEFORE the pngData image branch — a Finder Cmd+C on an image file
  carries fileURLs + bitmap together, so it lands `.file`.
- The string branch classifies only color / http(s) URL / text — a plain
  filesystem path string (Finder ⌥⌘C Copy as Pathname, terminal, chat
  apps) lands `.text` and now renders as monospaced text via the
  code-highlight branch. This literally shows the path — prime match for
  the user's wording.
- displayKind (color fix) only resolves .text/.rtf → color; untouched
  otherwise.

## Reproduce FIRST — classification matrix

Extend your existing synthetic-snapshot harness (ClipboardPayloadReaderTests):

1. Finder-style copy: fileURLs + pngData both present → today: `.file`.
2. Plain path string `/tmp/…/image.png` (existing PNG) → today: `.text`.
3. `file:///tmp/…/image.png` string → today: `.text` (detectURL is
   http/https only).
4. Bitmap-only copy (screenshot/browser Copy Image) → today: `.image`
   (verify — should already work).
5. Non-image controls: existing PDF path, non-existent path, prose with
   a path-looking token → must NOT become image-ish.

Red = the cases where the user would see a path/text but the file is a
real image. Establish the matrix before touching code.

## Fix requirements

- For every red cell, the CARD MUST SHOW THE IMAGE (thumbnail like the
  existing `.image` preview), both normal and compact, light and dark.
- Preserve paste semantics: a copied FILE must still paste as a file
  (Cmd+V of fileURLs into Finder). Prefer keeping kind `.file` for
  file-based payloads and rendering a thumbnail in the `.file` preview
  (load through ClipImageStore, async, same no-main-thread-disk-read
  rule) over reclassifying to `.image` — BUT make the call based on your
  repro and paste-path tracing (check PasteEngine.write for .file vs
  .image and state what each would paste). Whichever you choose, paste
  behavior must remain correct — that's a hard constraint.
- Path strings that point at an existing image file should also show the
  image (decide the kind: likely `.file` so paste stays file-correct;
  guard with a bounded existence + content check — classification runs
  on the background queue, keep it cheap: no loading image data at
  capture, existence/extension check only).
- Non-image paths and prose stay exactly as today. Code-highlight
  behavior for genuine code unchanged.
- If dataPath files are missing for existing `.image` rows (retention
  pruning?), check and report honestly — don't paper over it.

## Verification gate (your own output, quoted)

1. `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug build 2>&1 | grep -E "(warning|error)" | grep -iE "payloadreader|itemcard|clipimage"` → nothing.
2. `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug test 2>&1 | tail -5` → `** TEST SUCCEEDED **`, 208 existing + new, 0 failures.
3. Offscreen render evidence PNGs in /tmp/: image cards for at least a
   Finder-copied image (thumbnail shown, not filename/path) + a
   pathname-string copy (image shown), normal + compact. State exactly
   what they show.

## Handoff

Branch `feature/image-preview` off current HEAD. Commit with the real
root cause in the message. Report: matrix (red→green), root cause, kind/
paste decision + your reasoning, files changed, your own build/test
output, PNG paths, remaining manual checks.

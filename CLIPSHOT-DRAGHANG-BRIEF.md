# Bug: dragging an image card to a browser hangs both Clipshot and the browser

Project root: /Users/ernest/projects/clipboard (this IS the working directory)
Current HEAD: `d003658` on `main` (2 ahead of origin). Branch `feature/drag-out-hang`
FROM THIS HEAD.

## User report (verbatim)

"I tried dragging an image to the browser, it hanged half way, both my browser and
the clipshot app hanged. Had to force quit brave browser and stop xcode build for
Clipshot. Also i saw it was dragging the entire card not just the image"

## Context

- This is the P0-7 acceptance test (PASTE-PARITY-PLAN.md item 7, shipped PR #9
  `481c5c3`: drag-out via NSItemProvider with file URL + bitmap, plus "Paste as File").
- Test run 2026-11-07 against the installed cert-signed build
  (`~/Applications/Clipshot.app`, built 2026-11-03). Target page was a local
  `file://` page with an `<input type=file>` + drop zone that shows received
  filenames.
- Observed: hang mid-drag in BOTH apps; user had to force-quit Brave and kill a
  running `xcodebuild` (provenance of that xcodebuild unknown — possibly a leftover
  build; all agent-driven test runs had completed by then).
- Second round, same session (no hang this time, 2 source items):
  - Image item sourced from **Finder**: drag never starts — "cannot drag it" at all.
  - Image item sourced from **Cursor**: drag starts (ghost moves) but the drop
    delivers nothing to the target page — no filename received.
  So the defect is not only the hang: drag-out fails to initiate for `.file`-kind
  items and fails to deliver payload for others. Cover both kinds in the repro.
- Secondary observation: the drag payload renders as the entire item card, not just
  the image. Decide whether that's the intended drag preview (NSItemProvider drag
  image is allowed to be the card) or a symptom of the wrong payload being handed to
  the drag session — note it in the fix PR either way.

## Suspects to check FIRST (hypotheses, not conclusions — verify before acting)

- Synchronous temp-file copy for the `public.file-url` provider running on the main
  thread inside the drag session (plan flagged "temp-file lifecycle in
  ItemDataStore — mind the retention/orphan findings").
- A file-coordination / lock deadlock: Clipshot holding the temp file open while
  Brave waits to read it during drop, and Clipshot's main thread blocked on the
  drag-session callback meanwhile.
- Large PNG bitmap provider being materialised twice (file URL + bitmap) for a
  ~5 MB screenshot.

## Reproduce

1. `screencapture -x /tmp/x.png && osascript -e 'set the clipboard to (read (POSIX file "/tmp/x.png") as «class PNGf»)'`
2. Open the overlay (⌘⇧V), drag the image card toward any drop target that accepts
   files (local page with `<input type=file>`, or Finder window).
3. Current behaviour: beachball in Clipshot + target app mid-drag.

## Root cause lead — hard CRASH, not a hang (crash reports pulled 2026-11-07)

Three identical crash reports in `~/Library/Logs/DiagnosticReports/`:
`Clipshot-2026-11-07-141515.ips`, `-142411.ips`, `-142632.ips` (all three today,
one per app instance the user tested against — pids 22916 / 51540 / 78907).

All three:
- `exception.type: EXC_BREAKPOINT (SIGTRAP)`, `termination.code 5`,
  faulting thread varies (2 / 5 / 7) but the frame chain is identical:
  - `Foundation  static URL._unconditionallyBridgeFromObjectiveC(_:)`
  - `SwiftUI  specialized closure #1 in static PasteboardUtility.loadFileSystemItem<A>(from:contentType:completion:)`
  - `libswiftUniformTypeIdentifiers  thunk ... (URL?, Bool, Error?) -> ()`
  - `Foundation  __83-[NSItemProvider loadInPlaceFileRepresentationForTypeIdentifier:completionHandler:]_block_invoke.91`
  - libdispatch serial-queue drain frames
- System log shows a drag session starting seconds before the crash
  (`com.apple.ensemble.dragserver` + `com.apple.windowmanager.dragserver`
  connections, then `com.apple.foundation.filecoordination` claim, then the
  process dies — e.g. 14:26:31 dragserver → 14:26:32 crash).

So: force-unwrap of a nil/invalid file URL while an NSItemProvider file
representation is loaded during a drag. The user-perceived "hang" is the app
dying mid-drag (drag source freezes, target app waits on a dead provider — Brave
had to be force-quit). First question to settle in the fix: which side calls
`loadFileSystemItem` — drag-OUT payload materialisation in Clipshot's timeline
`.draggable`, or a SwiftUI drop handler on the overlay receiving an incoming
drag. The stack is SwiftUI's pasteboard *reading* path, so check drop-in support
first even though the report came from drag-out.

## Acceptance

- Drag completes: drop lands in <2 s, no beachball in either app, target shows the
  received filename with a plausible byte count.
- Temp file lifecycle: no orphaned temp files after drag completes OR is cancelled
  (test both paths).
- Full suite green (331 tests baseline) + a regression test covering the provider's
  temp-file path (unit-testable seam: path creation/lifecycle, not the drag itself).
- Report the verdict on the "entire card vs image" observation.

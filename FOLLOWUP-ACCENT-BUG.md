# Bug fix: every card shows a RED accent, not the source app's real accent color

User report (verbatim): "It's all showing a red card, which is not the color of the app".

Symptom: in the timeline, item cards are tinted red regardless of which app the clip came from. Expected: each card's accent derives from that app's icon color (e.g. Safari clips ~blue, Notes ~yellow), and color-kind items use the parsed color.

Project: /Users/ernest/projects/clipboard. Bug-fix work — commit directly on main when verified (no feature branch needed).

## Required approach — reproduce first, no speculative rewrites
1. Write a throwaway diagnostic (scratch swift script or xcodebuild test) that runs `AppIconAccent.dominantAccent` over the REAL icons of several installed apps (Safari, Finder, Notes, Terminal, Xcode — resolve via NSWorkspace.urlForApplication + NSWorkspace.shared.icon(forFile:)) and prints the resulting RGB per app. This tells us immediately whether extraction itself is wrong (all red), or the wiring/tint layer is.
2. Then inspect the likely culprits, in order:
   a. `ItemCard.accentColor` wiring — is the parsed-color rule leaking to non-color items, or is a constant/fallback `Color.red` used anywhere in the tint path (TimelineView, hover/selected states, context menus)?
   b. `AppIconProvider.ensureLoaded` — cache correctness: does the on-disk accent/icon cache (~/Library/Application Support/Clipshot/AppIcons) contain stale or cross-contaminated entries from earlier runs? Check `Self.fileURL` keying and whether a partial/failed earlier build wrote bad data. If in doubt, bump the cache version (e.g. suffix `.v2.png` / `.v2.accent`) so old cache entries are ignored, and clear the directory on launch once.
   c. `NSImage.cgImage(forProposedRect:)` on NSWorkspace icons: the icon NSImage has multiple representations; verify which one we're sampling (should be a reasonably sized one, not a 16px template). If the sampled representation is wrong, render into a fixed 64pt rect at 2x first.
   d. Premultiplied alpha / colorspace: verify the 64px sampling context against a known-color icon (the unit test uses solid red — make the test cover solid BLUE and solid GREEN too, so "always returns red" can never pass again).
3. Fix the root cause (only the root cause — no UI redesign).
4. Add regression tests: dominantAccent on solid blue image → blue-ish, solid green → green-ish, solid red → red-ish (hue preserved within tolerance). If the bug was in the view wiring, add a test or a preview-verifiable check for that path where feasible.
5. Manual verification: build, launch the app, copy items from 2+ different apps, and confirm via a screenshot (`screencapture` of the overlay or app window) that the tints differ per source app. Save the screenshot under /Users/ernest/projects/clipboard/Docs/verify-accents.png as evidence. If launching/capturing is not feasible in this environment, say so explicitly and explain what you verified instead — do NOT claim visual confirmation you didn't do.
6. Gate: `xcodebuild -scheme Clipshot build` AND `xcodebuild -scheme Clipshot test` pass. Commit on main with message "Fix per-app card accent: always-red tint root cause <X>" (describe actual root cause), update TESTING.md's accent check item.

## Constraints
Same as always: confine changes to /Users/ernest/projects/clipboard, no global installs, no fabricated results, list files changed + test counts + the true root cause in the final message.

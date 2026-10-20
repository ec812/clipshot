# Task: full OG metadata for links + Swift 6 concurrency fixes + capture latency

Branch: `feature/full-og-metadata` off main. All three items on this branch; report the branch name and I'll merge after verification.

## 1. OG metadata — image + title + description (user: "If it is a link, always get all the OG image, title and description if available")
- Extend the existing OG parser/loader to capture, per URL: og:image, og:title, og:description (with twitter:image / twitter:title / twitter:description and plain <title>/<meta name="description"> as fallbacks, in that order). Skip og:site_name etc.
- URL cards always show, when available: OG image thumbnail (existing), then title (bold, 1 line), then description (secondary, 2 lines). Partial metadata is fine — show what exists.
- Persist the full metadata record (image data + title + description JSON) in the existing OG disk cache with same TTL/negative-cache semantics. No second network request for metadata — one page fetch gets everything.
- Settings toggle stays the same ("Fetch link previews"); description respects it.

## 2. Swift 6 concurrency errors (user sees these in Xcode)
In AppState (and anywhere else with the same pattern):
- "Reference to captured var 'self' in concurrently-executing code; this is an error in the Swift 6 language mode" (×2)
- "Reference to captured var 'loaded' in concurrently-executing code; this is an error in the Swift 6 language mode" (×3)
Fix them properly (explicit self capture with [weak self]/[unowned], make `loaded` immutable or move it behind the actor boundary, adjust isolation) — NOT with @unchecked Sendable, nonisolated(unsafe), or by reverting Swift language mode. Grep the whole target for similar `var` captures inside Task.detached/Task{} closures and fix those too, so the codebase is Swift-6-clean even though SWIFT_VERSION stays 5.x for now. Show the remaining warning count before vs after (xcodebuild output grep 'warning:') in your final message.

## 3. Performance — copied items appear late (user: "the copied items do not immediately shows in the app after I copied something")
Investigate the whole capture→visible pipeline and make it feel instant:
- ClipboardMonitor poll interval (0.3s?) — reduce to ~0.1s and confirm CPU stays negligible; consider checking changeCount from a timer with tolerance, not a busy loop.
- Check every hop: pasteboard snapshot (main), hashing (off-main), DB insert (off-main), then the published items refresh reaching TimelineView — find where the delay actually is (log timestamps at each stage: copy observed → DB committed → UI list updated).
- The UI list should update from the already-known pipeline result, not re-query on a slow path; verify the @Published/revision chain actually fires on insert.
- Measure and report real numbers: time from a simulated copy to the item being visible in the list (add a temporary timing log, run it, quote the numbers). Target: <150ms p50 locally.
- Remove the temporary timing logs after measuring (keep a compact version behind a Debug flag if useful).

## Gate + evidence
- `xcodebuild -scheme Clipshot build` + `xcodebuild -scheme Clipshot test` pass; add/extend tests for the metadata parser (og + twitter + head fallbacks, missing fields, relative URLs) and cache record round-trip.
- Live check: launch, copy a URL with rich OG (e.g. a news article), screenshot the card showing image+title+description → Docs/verify-og-full.png; quote the measured copy→visible latency numbers.
- Update TESTING.md. Final message: branch, files changed, test counts, warning counts before/after, latency numbers, deviations.

Same constraints: workspace-only, no global installs, no fabricated results.

# Feature: horizontal scroll input for the timeline

Project root: /Users/ernest/projects/clipboard (this IS the working directory)

## What the user wants

The Clipshot timeline is a horizontal strip of cards. Let the user scroll it
left/right with BOTH of these input types:

1. **Vertical scroll wheel** (ordinary mouse, scrolling up/down) positioned
   over the timeline → should scroll the timeline LEFT/RIGHT instead of
   doing nothing. Scrolling "down" moves the strip forward (to the right).
2. **Horizontal scroll input** — a mouse with a horizontal/thumb wheel
   (Logitech MX Master 3 etc), trackpad two-finger horizontal swipe, or a
   tilt wheel → should scroll left/right natively. Verify this works today;
   if it doesn't, fix it.

## Where the code is

- Timeline (main target): `Clipshot/UI/TimelineView.swift:325-370`
  — `ScrollView(.horizontal, showsIndicators: false)` wrapping a
  `LazyHStack`. This is the primary thing to make scrollable both ways.
- Filter chip bar (secondary, also horizontal): `TimelineView.swift:216-217`.
  Apply the same treatment only if it's low-risk; the timeline is the
  must-have.

The app is SwiftUI (macOS). The rest of the app has no vertical scroll views
— the only two ScrollViews are both horizontal — so a scoped fix is fine.

## Implementation guidance

A common, scoped approach: an `NSViewRepresentable` that finds/hosts the
underlying `NSScrollView` and subclasses it to override `scrollWheel(with:)`.
When the event is vertical-dominant (`abs(deltaY) > abs(deltaX)`), map the
vertical delta onto horizontal content scrolling; when it's
horizontal-dominant (real horizontal-wheel devices), let it scroll
horizontally too. Respect natural-scrolling direction and don't fight
Shift+scroll (macOS already maps that to horizontal).

Hard constraints:
- Do NOT globally swizzle `NSEvent` or hook the whole app — scope it to the
  horizontal scroll views only.
- Preserve trackpad smooth scrolling and momentum (handle `phase` /
  `momentumPhase` correctly — momentum must keep gliding, not stop dead).
- Don't break card selection / click / context-menu behaviour on the cards.

## Verify before claiming done

- Build must be clean:
  `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug build 2>&1 | grep -E "(warning|error)" | grep -i timeline`
  → must return nothing.
- Tests must pass:
  `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug test 2>&1 | tail -5`
  → `** TEST SUCCEEDED **`, still 144+ tests, 0 failures.
- You can't physically move a mouse — if feasible add a unit test that
  constructs a synthetic `NSEvent` (vertical-dominant deltas) and asserts
  the override scrolls horizontally; otherwise state plainly that behaviour
  needs manual verification and give short manual test steps for the user
  (real mouse wheel over timeline = scrolls left/right; MX Master thumb
  wheel = scrolls left/right; trackpad two-finger horizontal = still smooth).

## Handoff

This is a NEW FEATURE → put it on a branch `feature/horizontal-scroll`
(branch off main). Do NOT push, do NOT re-init git. Commit with a message
stating what changed. Report back: branch name, files changed, build/test
results, and whether manual verification is still needed.

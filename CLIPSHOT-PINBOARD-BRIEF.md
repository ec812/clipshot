# Bug: pinboard add/rename not visible in the UI (pinboard "Remote")

Project root: /Users/ernest/projects/clipboard (this IS the working directory)
Branch: current checkout — whatever branch is checked out when you start
(likely feature/image-preview); stay on it, commit there.

## User report (verbatim)

"I added something to the pinboard (Remote) but it is not showing the
text in the pinboard. I have also edited its name, but there is nowhere
to be seen."

Interpretation: (a) an item added to pinboard "Remote" doesn't appear
when viewing that pinboard — and/or its text isn't shown; (b) renaming
the pinboard doesn't show the new name anywhere. Both point at UI state
not refreshing after successful DB writes — but VERIFY, don't assume.

## What I traced (binding prior work)

- `HistoryStore.renamePinboard` (HistoryStore.swift:438) does a plain
  UPDATE; `addItem(_:toPinboard:)` (:453) sets pinboardId + isPinned=1;
  `items(inPinboard:)` (:471) queries by pinboardId. SQL looks right.
- `AppState.addToPinboard` (AppState.swift:412) → performStoreWrite →
  completion shows toast "Added to X" only. `AppState.pinboards` is
  @Published (line 50), loaded in reload() (lines 250-262).
- Prime suspects: (1) completion paths don't trigger reload()/pinboards
  refresh so @Published state stays stale after rename/add; (2) the
  filtered view (filterPinboardID, AppState:246) or an active search
  query hiding the item; (3) a second running app instance (stale
  LSUIElement instances were a v1 bug — SingleInstanceGuard exists)
  serving the UI while the write landed elsewhere; (4) rename UI not
  wired to reload at all.

## Reproduce FIRST

Build a failing test or instrumented repro against real AppState +
HistoryStore: create pinboard "Remote", add a TEXT item, assert
`pinboards` and the filtered item list reflect it WITHOUT waiting for an
unrelated event; rename → assert published name updates. Also check the
UI call sites: which closure renames (AppState.renamePinboard caller?)
and does it refresh? Establish where the chain breaks before fixing.
If a live-app interaction is genuinely required and cannot be
synthesized, say so plainly and give the user a precise manual check.

## Fix

- Fix ONLY the discriminated cause; every successful pinboard write
  (add, remove, rename, create, delete) must leave published state
  consistent with the DB immediately.
- The item's text must be visible when viewing its pinboard (if the
  repro shows text missing for another reason — e.g. preview branch —
  fix that instead, state what you found).
- Search/filter interactions: if an active search/filter legitimately
  hides the item, that must be obvious (e.g. clearing filter shows it) —
  document whatever behavior you preserve.

## Verification gate (your own output, quoted)

1. `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug build 2>&1 | grep -E "(warning|error)" | grep -iE "appstate|historystore|timeline|itemcard"` → nothing.
2. `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug test 2>&1 | tail -5` → `** TEST SUCCEEDED **`, all existing + new tests, 0 failures. (If CodeSign/"code object is not signed at all" flake appears: `clean` then retest, note it.)
3. Red→green evidence for the repro test.

## Handoff

Commit on the current branch; message states the real root cause.
Report: root cause, files changed, your own build/test output, remaining
manual checks.

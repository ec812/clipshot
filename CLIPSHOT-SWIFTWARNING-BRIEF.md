# Fix Swift warning: "Capture 'self' was never used"

Project root: /Users/ernest/projects/clipboard (this IS the working directory)

## The warning

`Clipshot/App/AppState.swift`, in `start()` (around line 159-186):

```swift
Task.detached(priority: .userInitiated) { [self] in
    ...
}
```

Xcode reports: **Capture 'self' was never used** (reported at the closure, warning surfaces near the `self.applyHotkeys()` call site ~line 180).

## The fix

Remove the redundant explicit `[self]` capture from the `Task.detached`
closure — it's already a non-escaping-style reference to the enclosing
class instance and the explicit capture is what the compiler flags as
unused. Do NOT change any logic, control flow, or the `MainActor.run`
blocks inside. This is a warning-only cleanup.

## Constraints

- Only touch this one closure in AppState.swift — no drive-by refactors.
- Do NOT run `pod install`, package updates, or anything that mutates
  global state.
- Do NOT push or re-init git.

## Verification (required before claiming done)

Build the app and confirm the warning is gone AND no new warnings/errors
are introduced:

```
xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug build 2>&1 | grep -E "(warning|error)" | grep AppState
```

Must return nothing. Also run the test suite:

```
xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug test 2>&1 | tail -20
```

## Handoff

Commit on the current branch with a message stating what changed (e.g.
"Remove redundant [self] capture in AppState.start() Task.detached").
Report back: files changed, build/test results, any deviations.

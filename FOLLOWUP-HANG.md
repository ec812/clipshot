# Bug: Clipshot app hangs (user had to force-stop pid 57609)

User report: "The process 57609 hanged (clipshot)" — he stopped it manually. It was launched from Xcode (parent = debugserver), ran ~19 minutes, then appeared hung.

## Evidence I collected before it was killed
1. `sample 57609` (saved at /Users/ernest/.hermes/cache/scratch/clipshot-hang.txt): at sample time ALL 5 threads were idle — main thread parked in `ReceiveNextEventCommon` / CFRunLoop (normal event loop), NSEventThread waiting, 0% CPU, state SX, footprint 51.5M (peak 367.3M). NO Clipshot frames blocked anywhere → at that instant there was no lock deadlock; the process looked "quiet", not spinning.
2. Unified log (`log show --last 22m --predicate 'process == "Clipshot"'`) shows TWO different pids: 57609 (the hung one) and 9177 (an earlier instance, still logging at 19:49 — CoreSpotlight/AppIntents donations, then `AppKit:AutomaticTermination ... _kLSApplicationWouldBeTerminatedByTALKey=1`).
3. So key hypotheses to test, in order:
   a. **Multiple instances**: earlier instances left running (Xcode relaunches without killing the old one; menu-bar apps survive Xcode stop if LSUIElement). Two instances fighting over: status item, global hotkeys (Carbon RegisterEventHotKey — second registration silently fails or the DEAD one keeps the hotkey), pasteboard monitoring, same SQLite database (GRDB/WAL lock contention → writes blocking → UI appears frozen on a DB call on main thread).
   b. **Main-thread I/O**: any GRDB/HistoryStore call or disk read (OG cache, ItemDataStore, icon cache) performed synchronously on the main actor — under lock contention with a second instance this blocks the UI while the run loop sits idle between... (verify by checking which store calls are made on main).
   c. Xcode/debugserver-related stall (less likely, but note the app was under debugserver).
   d. Automatic termination weirdness with LSUIElement menu-bar apps.

## Required
1. Reproduce: launch the app (debug build is fine), confirm what a healthy run looks like; then relaunch WITHOUT quitting the first (simulate the Xcode-restart case) and see if the second instance wedges or if both end up sharing hotkeys/status item. Check GRDB behavior with two processes on one DB file.
2. Root-cause the hang class, and implement defenses regardless of which one reproduces:
   - Single-instance guard: on launch, detect a running Clipshot (distributed notification / NSRunningApplication / lock file with pid) and either activate+exit the newcomer, or kill/replace the stale one cleanly. Menu-bar apps must never double-run.
   - Make sure NO store/cache/disk operation runs synchronously on the main actor (grep for `Data(contentsOf:`, `String(contentsOf:`, store reads in view bodies). Move to background with results published back.
   - GRDB: verify WAL mode + busy timeout (`Database.busyTimeout`) so a second process can't wedge readers/writers.
   - Hotkey registration: if registration fails (already taken by our own stale instance), surface it (log + settings warning) instead of silently doing nothing.
3. Verify: build+test gate passes (`xcodebuild -scheme Clipshot build` / `test`), then a live check: start the app, start a second copy, confirm exactly one instance survives and the survivor's hotkeys/status item work (report how you confirmed — log lines are fine, no visual claim beyond what you did).
4. Commit on main: "Fix app hang: <actual root cause>". Files changed, test counts, deviations in the final message.

Same constraints: workspace-only, no global installs, no fabricated results. If you cannot reproduce the hang at all, say so explicitly and ship the defensive fixes anyway, documenting what you tried.

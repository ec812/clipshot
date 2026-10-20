# Bug batch: SQLite disk-I/O error during search + DB resets on every Xcode rebuild + links still slow to appear

User report (verbatim, three issues):
1. "when I am searching I get Clipshot SQLite error 10: disk I/O error - while executing *PRAGMA query_only = 1*"
2. "the sqlite always resets when I rebuild the app in xcode, which is not necessary" — history is wiped on every rebuild; it should persist.
3. "links still take a long time to appear in the app" — URL items specifically lag behind text items in showing up.

Work on main (bug fixes). These are correctness bugs — root-cause them, don't band-aid.

## What to investigate, in order
1. **DB path stability.** Log/print the actual DB path at launch in two consecutive builds (Xcode build+run, quit, build+run again). It must be a stable path under ~/Library/Application Support/Clipshot/. If it's build-dependent (bundle-UUID, container URL, or derived from the app's path/signature) that explains BOTH the reset and the IO error (old connection's WAL/SHM orphaned when the path moves). Also check whether anything recreates the DB from scratch on migration mismatch (deferred migrations from the hang fix — verify they detect an existing schema correctly and never DROP/recreate).
2. **The PRAGMA query_only = 1 error.** GRDB issues this when preparing a read-only connection. Disk I/O error there means the connection's file (or its -wal/-shm) vanished or was replaced under it. Likely interaction with (a) the DB being recreated at a new path, and/or (b) the single-instance guard letting a stale instance hold connections while Xcode relaunches a new one, and/or (c) Xcode SIGKILL on stop leaving WAL in a bad state that our code "recovers" by deleting. Whatever the chain: never delete/recreate the DB as recovery; implement proper open-failure handling (retry, log with full error, surface a visible error state instead of silently resetting).
3. **Persistence across rebuilds.** Test explicitly: launch build A, copy 3 items, quit (both gracefully and via Xcode stop = SIGKILL), relaunch build B → items must still be there. Add a unit/integration test: write items → close DB → reopen with a fresh DatabaseQueue on the same file → rows persist and migrations are no-ops.
4. **Link latency.** URL items must appear in the timeline as fast as plain text (card shows the raw URL immediately; OG image/title/delivery enrich the card afterward). Find why URL items specifically are delayed — suspects: URL parsing/classification before insert, network work touching the insert path, or the preview store blocking first paint. Measure copy→visible for a URL specifically (same timing method as before) and quote numbers before/after.

## Gate
- `xcodebuild -scheme Clipshot build` + `xcodebuild -scheme Clipshot test` pass; new tests: DB reopen persistence, migration idempotency, no-recreate-on-corrupt-WAL behavior (simulate by opening/closing with WAL files present), URL latency path doesn't await network.
- Live: build via xcodebuild (not Xcode UI if you can't drive it), copy items, kill -9, relaunch from the NEW build, confirm items persist; then search and confirm no SQLite error (check logs). Quote the evidence.
- Commit on main (one commit per logical fix is fine): state actual root causes in messages. Update TESTING.md with the persistence-across-rebuild check.

Same constraints: workspace-only, no global installs, no fabricated results. If the reset turns out to be caused by something outside the app (e.g., Xcode scheme deleting Application Support — check the scheme's pre-actions!), say so and fix the scheme config instead.

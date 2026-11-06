# Feature brainstorm: detect copied code + syntax highlighting in the card preview

Project root: /Users/ernest/projects/clipboard (this IS the working directory)
Branch: main (create `feature/code-highlight` when implementation starts).

## Process requirement — READ FIRST

Run a proper brainstorming/design phase BEFORE any implementation. The
user is at this terminal and will answer your questions interactively in
this session. Rules:

1. Explore project context first (CardChrome/ItemCard preview rendering,
   ClipboardItemKind, how `.text` items render, Stores/Services layout,
   Docs/ conventions).
2. Ask clarifying questions ONE AT A TIME, multiple choice preferred.
   Wait for the user's reply after each — do not batch questions, do not
   implement anything while questions remain.
3. Then propose 2-3 approaches with trade-offs and your recommendation.
4. Present the design in sections, get the user's approval after each.
5. Write the approved design to `Docs/` (follow existing Docs/ layout,
   e.g. the superpowers plans/specs pattern already in the repo) and
   commit it.
6. ONLY after explicit user approval of the design, create
   `feature/code-highlight`, write the implementation plan, and implement.

HARD GATE: no code, no scaffolding, no implementation before the user
approves the design in this session.

## Feature intent (starting point, not decisions)

When the user copies text that is actually CODE, the card should detect
that and render the preview with syntax highlighting. Open questions you
must explore with the user (not decide yourself):

- Detection: heuristic (brace/indent/punctuation patterns, language
  keywords) vs user toggle vs both? Where does it run (capture time vs
  render time)? Must not slow capture.
- Scope: which languages first? What counts as "code" vs plain text?
- Rendering: AttributedString styling vs a lightweight dependency? The
  repo currently has ONE dependency (GRDB) — weigh adding a package
  heavily; native SwiftUI Text with attributed runs is likely preferred,
  but propose options honestly.
- Where: highlight the card preview only, or also Quick Look / overlay?
- False positives: prose with occasional punctuation (emails, prose with
  dashes) must not get highlighted — ask for the user's tolerance.

## Constraints

- Capture path performance is sacred — no heavy parsing on the clipboard
  monitor hot path.
- Existing behavior for non-code text must be unchanged.
- Keep the test-count invariant: existing 152 tests must all still pass.

## Handoff

Design approved → branch `feature/code-highlight` → implement → same
verification gate as always (filtered build grep prints nothing; full
suite `** TEST SUCCEEDED **` with count = 152 + new tests) → commit.
Report branch, files, your own build/test output, and manual checks.

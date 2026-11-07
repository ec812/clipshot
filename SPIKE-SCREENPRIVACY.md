# Spike: screen-sharing / recording privacy (P1 item 8)

**Date:** 2026-11-07  
**Branch:** `feature/spike-screen-privacy` (off `main` @ `cdaf1a7`)  
**Scope:** investigation only — no app or Settings changes in this pass.

## Product intent (from `PASTE-PARITY-PLAN.md`)

Paste ships a **“Show during screen sharing”** style control: while the display is being shared or recorded, the clipboard manager should **not** expose sensitive history (and Clipshot’s overlay is especially visible). Clipshot already has **manual privacy pause**, bundle/concealed-type filtering, and pause-gated network fetches; item 8 asks for **automatic** awareness of share/record sessions.

**Honest constraint:** Apple documents no API for “is my screen currently being captured or viewed by another party?”

---

## Approaches evaluated

### 1) `CGWindowListCopyWindowInfo` + `kCGWindowSharingState` polling

**What the API actually means:** `kCGWindowSharingState` reflects each window’s **sharing type** (`NSWindow.sharingType` / `setSharingType:`), i.e. whether *other apps may capture that window via CoreGraphics*, not whether a share session is active.

| Constant | Value | Meaning |
|----------|-------|---------|
| `kCGWindowSharingNone` | 0 | Window opts out of capture (private) |
| `kCGWindowSharingReadOnly` | 1 | Normal windows (capturable) |
| `kCGWindowSharingReadWrite` | 2 | Rare; read/write sharing |

**TCC interaction:** Without **Screen Recording** permission on *our* process, window **names** are redacted and `kCGWindowSharingState` is often reported as **0** for all windows. With permission, states become meaningful for window privacy — still not “Zoom is sharing.”

**Throwaway probe** (`swiftc` harness on this Mac, Screen Recording granted for Terminal/Cursor):

```
CGPreflightScreenCaptureAccess: true
kCGWindowSharingState histogram: [(key: 1, value: 21)]
  loginwindow:  sharing=1
  Brave Browser: Clipshot P0-7 drop test … sharing=1
  Cursor: … sharing=1
  …
```

Every on-screen window was `1` (read-only). Nothing in the histogram changed during normal work; there is **no signal** that flips when a browser tab shares to Meet/Zoom.

**Verdict:** ❌ **Not viable** as the primary detector for “screen is being shared.” Wrong semantics; polling is noisy CPU with no reliable edge.

---

### 2) ScreenCaptureKit (SCKit) / `CGRequestScreenCaptureAccess`

**What it does:** Lets *our app* capture displays/windows/audio after the user grants **Screen Recording**. `SCShareableContent` enumerates capture targets; `SCStream.isCapturing` is **only true for streams we own**.

**What it does not do:** Report whether **another** process (Zoom, OBS, QuickTime, Chrome tab capture) is recording or transmitting.

`CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()` answer “**may Clipshot record the screen?**” — useful if we built capture, useless for third-party share detection. Requesting access solely to poll would be **user-hostile** (extra TCC prompt) with no detection payoff.

**Verdict:** ❌ **Not viable** for automatic hide-during-share. ✅ Relevant only if we later add our own capture feature.

---

### 3) TCC / system heuristics

**Ideas considered:**

| Heuristic | Reality |
|-----------|---------|
| List apps with Screen Recording TCC | No public API; private SPI (`tccutil`, `kTCCServiceScreenCapture`) is **App Store / notarization poison** and changes across OS releases |
| Watch `screencapture`, `screensharingd`, `replayd` | Processes may be up **without** an active share; QuickTime, screenshot tools, and background agents create false positives/negatives |
| Menu-bar “recording” pill | No public API; some tools scrape it via **Accessibility** (fragile, OS-string dependent) |
| iOS `UIScreen.isCaptured` | **No macOS equivalent** |

**Verdict:** ❌ No reliable TCC-only path. Any “heuristic bundle” must be **explicitly best-effort**, fail-closed to “not sharing” or require user confirmation.

---

### 4) Signals that *do* work (partial, app-specific)

| Signal | Coverage | Reliability |
|--------|----------|-------------|
| `NSDistributedNotificationCenter` **`com.apple.remotedesktop.viewerNames`** | Built-in **Screen Sharing** / ARD viewers | ✅ Good **only** for Apple remote desktop; empty when Meet/Zoom/Teams share |
| **Accessibility (AX)** on conferencing apps | Zoom (“Start/Stop Share” menu), Meet/Teams/Slack controls, Chrome tab indicators | ⚠️ **Medium** with ongoing maintenance; needs **Accessibility** permission; per-app selectors break on updates (see [Hush](https://github.com/stacksjs/hush), [Meeting Pulse](https://github.com/mknmohit/meeting-pulse)) |
| **Mic-in-use** as proxy | Some calls share mic + screen | ❌ Poor (false negatives: share-without-mic; false positives: voice notes) |

This matches industry practice: clipboard managers and “hush” tools combine **ARD notification + AX conference heuristics**, not CGWindow state.

---

## Recommendation

### Do **not** ship a Settings toggle that promises automatic “hide while screen sharing” based on CGWindow or ScreenCaptureKit alone.

Users would assume Paste-parity reliability; we would deliver false negatives (most Zoom/Meet shares) or false positives (unrelated Screen Recording grant).

### Viable product path (ordered)

1. **Ship now (no detection):** Treat **Privacy pause / “Presenting”** as the supported control — manual or timed, surfaced in menu bar and Settings copy. Clipshot already blocks capture and preview network while paused; extend UX (label, shortcut, optional default duration). **Effort: S.** **Reliability: 100%** for users who toggle it.

2. **Optional later — “Conference awareness (beta)”:** Opt-in second toggle, **only** when Accessibility is trusted. Background reducer (meet-style apps) merging:
   - `com.apple.remotedesktop.viewerNames` (free, narrow)
   - AX trees for Zoom / Slack / Teams / Chrome+Meet (high maintenance; versioned selector table in app, unit tests with **fixture AX dumps** where possible)
   - Debounce + fail-closed: if unsure → **do not** change overlay state; optional user override.
   **Effort: M–L.** **Reliability: good for listed apps, never complete.**

3. **Explicit non-goals:** Do not add Screen Recording TCC just to poll; do not claim CGWindow sharing-state detects global capture; do not block overlay based on “conferencing app is running” without share UI proof (would mute Clipshot all day).

### What shipping (2) would take

- `ScreenShareReducer` service + `PrivacyFilter` / `OverlayController` hook: when `sharingLikely == true`, hide panel or show chrome-only placeholder (design choice).
- Settings: master switch + “requires Accessibility” + link to System Settings.
- Selector manifest (`ConferenceAppSignature.swift`) with bundle IDs + AX queries; telemetry-free local logging for user bug reports.
- Tests: reducer fixtures from recorded `-[NSDictionary]` / JSON AX snapshots; manual matrix in `TESTING.md` (Zoom/Meet/Teams/ARD, start/stop share, app update).
- Copy: **“Best effort — use Presenting mode if you need a guarantee.”**

---

## Probe artifacts

| Artifact | Location |
|----------|----------|
| CGWindow / TCC preflight probe | `/tmp/screenprivacy_probe` (local throwaway; not committed) |

---

## Spike conclusion

| Approach | Viable for automatic toggle? |
|----------|------------------------------|
| `kCGWindowSharingState` polling | **No** — wrong meaning, no share edges |
| ScreenCaptureKit / SCR prompts | **No** — self-capture only |
| TCC / process heuristics alone | **No** — unreliable, no public TCC read API |
| ARD distributed notification | **Partial** — Apple Screen Sharing only |
| Accessibility conference heuristics | **Partial** — best available on macOS; opt-in + maintenance |

**Ship recommendation:** Implement **manual Presenting / pause UX** first (item 8 narrow MVP). Defer automatic detection to a **separate, opt-in “Conference awareness (beta)”** project only if product accepts ongoing selector maintenance and honest “best effort” messaging.

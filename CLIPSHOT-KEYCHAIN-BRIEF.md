# Bug: Bitly access token save fails — "Clipshot Keychain error 100002"

Project root: /Users/ernest/projects/clipboard (this IS the working directory)
Branch: current checkout; stay on it, commit there.

## User report (verbatim)

"Also, Bitly, when I save the access token it says: Clipshot Keychain
error 100002 and it is not working at the moment"

## ⚠️ ABSOLUTE CONSTRAINT — KEYCHAIN SAFETY (violating this fails the task)

The user had a prior incident where CLI keychain manipulation corrupted
another app's encryption key. Therefore:

- NEVER run `security` CLI — no create/lock/unlock/scan/repair/delete of
  any keychain, no touching default-keychain settings, no login.keychain
  access from the terminal.
- NEVER write tests or scripts that CREATE/MODIFY/DELETE keychain items.
  No automated keychain repro at all.
- Diagnosis is: read code, reason about the OSStatus, add TEMPORARY
  LOGGING to the app's save path (full OSStatus + SecCopyErrorMessageString
  + which call failed: SecItemUpdate vs SecItemAdd), and have the USER
  retry Save in the app UI and report the console/toast output if needed.
- Any fix lives in app code for its own service `com.ernest.clipshot`,
  or is UI guidance the USER performs in System Settings > Passwords.

## What I traced (binding prior work)

- The toast text "Keychain error <status>" comes solely from
  `KeychainError.status(OSStatus)` in Clipshot/Services/KeychainStore.swift
  (:15) — so a raw SecItem call returned OSStatus **100002** (positive,
  non-standard — errSec codes are negative). It throws from
  `setAPIKey` : SecItemUpdate failure (:71) or SecItemAdd failure (:69).
- KeychainStore: generic password, service `com.ernest.clipshot`,
  account `<backendId>.api-key`, `kSecAttrAccessibleAfterFirstUnlock`,
  plain file-keychain (NO `kSecUseDataProtectionKeychain`), no
  kSecAttrSynchronizable. Debug builds are ad-hoc signed ("Sign to Run
  Locally").
- Context that may matter: the user's system had a keychain-damaging
  incident in June 2026; positive/odd statuses can indicate a damaged or
  locked keychain environment rather than a code bug. Investigate both
  code-level and environment-level hypotheses.

## Investigation order

1. Determine what OSStatus 100002 actually is (search the web if needed;
   check SecCopyErrorMessageString output paths, Apple errSec tables,
   known issues with SecItem on macOS 14+ / ad-hoc-signed apps / data
   protection keychain).
2. Read BitlyBackend/Settings save flow — WHEN is setAPIKey called (on
   every keystroke? after validation?), what backendId, and whether the
   error shown is actually from a different layer mislabeled.
3. Code-level candidates to evaluate (not assume): missing
   kSecUseDataProtectionKeychain for modern macOS, accessibility/ACL
   issues for ad-hoc-signed Debug builds, stale item with mismatched
   attributes breaking SecItemUpdate, needing kSecUseDataProtectionKeychain
   migration, app sandbox entitlements (check Config/ + entitlements files).
4. If code fix applies → implement + explain in report what the user
   must do in System Settings UI if any manual step is needed (spell out
   exact clicks — but YOU never touch it).
5. If the cause is environment damage → say so honestly, give the user
   the exact System Settings UI steps, and make the app's error message
   ACTUALLY HELPFUL (include the OSStatus name/message via
   SecCopyErrorMessageString instead of a bare number, plus a hint where
   to look).

## Verification gate (your own output, quoted)

1. Build: `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug build 2>&1 | grep -E "(warning|error)" | grep -iE "keychain|bitly|settings"` → nothing.
2. Tests: `xcodebuild -project Clipshot.xcodeproj -scheme Clipshot -configuration Debug test 2>&1 | tail -5` → `** TEST SUCCEEDED **`, all existing + new, 0 failures. NO keychain-touching tests — mock APIKeyStoring for save-flow tests instead.
3. If a manual UI step for the user is required, state it as numbered
   System Settings clicks.

## Handoff

Commit on the current branch; message states the root cause (or the
honest environment diagnosis + app-side hardening). Report: root cause
of 100002 (with evidence), files changed, your own build/test output,
the user's remaining manual steps.

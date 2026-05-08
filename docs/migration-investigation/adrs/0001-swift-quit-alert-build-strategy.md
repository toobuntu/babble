<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# ADR-0001: Swift quit_alert build strategy

- **Status:** Accepted
- **Deciders:** maintainer
- **Date:** 2026-05

## Context and problem statement

Babble shows a confirmation dialog before quitting an
`unsafe_to_quit: true` cask (the user might have unsaved
work). The dialog is a Swift program (`quit_alert.swift`)
that uses NSAlert with a custom icon — the visual feedback
needed (light/dark icon, app name, app icon) is hard to
produce with `osascript display dialog`.

The Swift binary needs to be available at babble's runtime.
There are several ways to get it there:

1. Pre-compile and ship in the repo
2. Auto-compile on first run via `xcrun swiftc`
3. Distribute as a separately-built homebrew formula
4. Use osascript display dialog as the fallback (no Swift)

The maintainer has no Apple Developer certificate, which
constrains options 1 and 3 (codesigning options).

## Decision drivers

- **Availability requirement:** the dialog must work on
  Apple Silicon and Intel macOS, on macOS 14+ (Sonoma+).
- **Distribution constraint:** no Apple Developer cert
  → cannot Developer-ID-sign binaries → ad-hoc-sign only.
  Ad-hoc-signed binaries with the `com.apple.quarantine`
  xattr are blocked by Gatekeeper on Apple Silicon
  (rosetta-translated x86_64 binaries are subject to the
  same policy).
- **First-run latency:** auto-compilation adds ~3-5 seconds
  to the first run, after which a cached binary is reused.
  Acceptable.
- **Dependency surface:** what babble assumes is available
  at runtime.
- **Failure mode:** if the Swift binary can't be compiled
  (missing xcode-command-line-tools, broken Xcode),
  babble must still function.

## Considered options

### Option 1 — Pre-compile and ship in repo

What refactor/modular did. `swift/build/dist/quit_alert_arm64`
and `quit_alert_x86_64` are committed.

**Pros:**
- No first-run latency
- Doesn't require xcode-command-line-tools at runtime
- Works on the maintainer's local machine

**Cons:**
- **Ad-hoc-signed binaries with quarantine xattr are blocked
  by Gatekeeper on Apple Silicon**
  (this is the dealbreaker)
- Maintainer has to build binaries for both architectures
  before each release
- Repo size grows with each binary
- Two binaries → two attack surfaces for review

**Disposition:** Rejected because of the Gatekeeper
constraint. Would require an Apple Developer cert
(~$99/year) plus a notarization workflow to make binaries
distributable.

### Option 2 — Auto-compile on first run via xcrun swiftc

PR #1 figured this out. On babble's first run that needs the
quit alert, check whether the compiled binary exists at
`$XDG_CACHE_HOME/babble/swift/quit_alert_<arch>` (or similar);
if not, compile it via `xcrun swiftc -O -o <output> swift/src/quit_alert.swift`.
Cache the compiled binary; reuse on subsequent runs.

**Pros:**
- No codesign issues — locally-compiled binaries don't
  carry the quarantine xattr
- Works on Apple Silicon and Intel (compile for the host
  architecture)
- No pre-built binaries in the repo
- First-run latency is ~3-5 seconds, acceptable
- Compiles for the actual host architecture (no fat binary
  needed)

**Cons:**
- Requires xcode-command-line-tools at runtime (or full
  Xcode). Most Homebrew users have this — many casks need
  it. Acceptable assumption.
- Slower first run (3-5 seconds for the compile)
- Cache invalidation: if the Swift source changes (in a
  babble update), the cached binary needs to be rebuilt.
  Solve via hash-of-source-file in cache filename, or
  delete-and-rebuild on babble version changes.
- Compilation can fail (broken Xcode, partial CLT install).
  Need a graceful fallback.

**Disposition:** Accepted as primary.

### Option 3 — Separate homebrew formula

Ship the Swift binary as its own formula (`babble-quit-alert`
or `quit-alert-helper`). babble's tap depends on it. Homebrew
builds it from source on the user's machine via the formula's
`install` block.

**Pros:**
- Properly versioned via Homebrew formula tagging
- Homebrew already handles the build-from-source workflow
- No additional caching logic needed in babble
- If the formula has issues, they're surfaced through
  Homebrew's normal error reporting

**Cons:**
- Adds a separate formula to maintain alongside the
  external-command tap
- More moving parts at install time
- Functionally similar to option 2 (still compiles from
  source) but with more ceremony
- Introduces a hard dependency that doesn't degrade
  gracefully if the formula fails to install

**Disposition:** Rejected. Option 2 achieves the same end
state with less infrastructure.

### Option 4 — Use osascript display dialog as primary

Skip Swift entirely. Use AppleScript's `display dialog` for
the quit confirmation.

**Pros:**
- Zero build dependencies
- Always available on macOS
- Simple to implement

**Cons:**
- AppleScript dialogs don't easily support custom icons
- Less polished visual presentation
- Limited button text customization
- Worse UX than the Swift NSAlert

**Disposition:** Rejected as primary, but useful as a
fallback when Swift compilation fails.

## Decision outcome

**Chosen: Option 2 (auto-compile via xcrun swiftc) with
Option 4 as graceful fallback.**

W3 implementation:

1. **Lookup or build the Swift binary** at first invocation:
   - Cache location:
     `$HOMEBREW_CACHE/babble/quit_alert_<arch>` (or
     `~/Library/Caches/Homebrew/babble/`)
   - Source: `<tap_dir>/swift/src/quit_alert.swift`
   - If cached binary exists AND source hash matches the
     cached version's hash, use the cache
   - Else compile via:
     ```
     xcrun swiftc -O -o <cache_path> <source_path>
     ```
     Plus log the compilation event (one-time, visible to
     user)
2. **On compilation failure**: catch the error from xcrun
   swiftc; fall back to `osascript -e 'display dialog
   ... with title "babble" buttons {"Cancel", "Continue"}
   default button "Continue"'`
3. **On osascript failure**: skip the prompt entirely; just
   quit the app. Log the skip with `opoo` so the user
   knows the unsafe_to_quit warning was bypassed.
4. **No pre-built binaries** in the repo. The Swift source
   file (`swift/src/quit_alert.swift`) ships in the tap;
   the binary is always locally-built.

## Consequences

**Good:**
- No codesign infrastructure needed
- No Apple Developer cert needed
- No notarization
- No fat binaries
- First-run UX is acceptable (3-5 second compile)
- Cached on subsequent runs
- Graceful degradation if Swift compilation isn't possible
- Easy to update the Swift source without re-releasing
  binaries

**Bad:**
- First run is slower than no-build cases
- Requires xcode-command-line-tools at runtime
  (acceptable Homebrew-user assumption)
- Compilation errors surface as runtime errors rather than
  install-time errors (mitigation: graceful osascript
  fallback)
- Cache management complexity (small; hash-based)

**Tradeoff acknowledged:** users without
xcode-command-line-tools fall through to the osascript
fallback. The fallback is functionally adequate but visually
less polished. This is a reasonable degradation given the
constraint of no-cert distribution.

## More information

- Homebrew Discussion on bootsnap cache (related transient
  failure rationale that drove `Babble::Retry`):
  https://github.com/orgs/Homebrew/discussions/5226
- Apple's notarization requirements:
  https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- Gatekeeper behavior on Apple Silicon:
  https://support.apple.com/en-us/HT202491

## Revisit triggers

- Maintainer acquires an Apple Developer cert (~$99/year):
  pre-built signed binaries become viable, possibly
  worth migrating to Option 1 with notarization
- macOS substantially changes its Gatekeeper policy
- Compilation latency becomes user-visible problematic
  (e.g., multiple compiles per session due to cache
  invalidation issues)

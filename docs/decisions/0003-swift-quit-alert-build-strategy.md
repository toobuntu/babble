---
# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

number: 3
title: Swift quit_alert build strategy
status: accepted
date: 2026-07-03
decision-makers:
  - toobuntu
---

# Swift quit_alert build strategy

## Context and Problem Statement

Before quitting an `unsafe_to_quit: true` app (the user might have
unsaved work), babble shows a confirmation dialog. The dialog is a
Swift program (`quit_alert.swift`, NSAlert with a custom light/dark
icon) — visual feedback that `osascript display dialog` cannot match.
The compiled binary must be available at babble's runtime on macOS 14+
(the Swift 5.9 source needs Xcode 15 to build), on Apple Silicon and
Intel.

The maintainer has no Apple Developer certificate. Ad-hoc-signed
binaries carrying the `com.apple.quarantine` xattr are blocked by
Gatekeeper on Apple Silicon, which rules out simply committing
pre-built binaries.

## Decision Drivers

* No Apple Developer cert → no Developer ID signing, no notarization.
* The dialog must work on both architectures, macOS 14+.
* First-run latency of a few seconds is acceptable; a broken Xcode
  install must not break babble entirely.
* Auto-compiling code on the user's machine is a trust delegation
  that must be verifiable and visible, never silent.

## Considered Options

* **Pre-compile and ship binaries in the repo** (what
  refactor/modular did).
* **Auto-compile on first run via `xcrun swiftc`**, cache the binary.
* **Separate Homebrew formula** that builds the helper from source.
* **`osascript display dialog` only** (no Swift).

## Decision Outcome

Chosen option: **auto-compile via `xcrun swiftc` with the osascript
dialog as graceful fallback**, because locally-compiled binaries carry
no quarantine xattr (no Gatekeeper/codesign problem), the compile
targets the actual host architecture, the ~3–5 s cost is paid once per
source change, and a compile failure degrades to a functional (if
plainer) osascript prompt instead of breaking babble.

Key mechanics (implementation lands with the Swift C-block):

* **Source ships in the tap** (`swift/src/quit_alert.swift`); no
  pre-built binaries in the repo.
* **SHA256 sidecar**: `swift/src/quit_alert.swift.sha256` is
  committed in SHA256SUMS format and user-verifiable with
  `shasum -a 256 -c`. At runtime babble hashes the source and
  **refuses to compile on mismatch**, with recovery instructions
  (`brew update`, or a helper script for intentional local edits).
* **Cache key embeds the source hash**:
  `$HOMEBREW_CACHE/babble/quit_alert_<arch>_<hash12>` — a source
  change auto-invalidates the cache and triggers a fresh
  verification + compile + transparency cycle.
* **Transparency on first compile**: babble prints the source path,
  target path, verified hash, and the exact `xcrun swiftc` command
  before compiling. No silent arbitrary code execution.
* **Fallback chain**: `xcrun swiftc` failure → osascript dialog;
  osascript failure → skip the prompt and warn via `opoo` that the
  unsafe-to-quit confirmation was bypassed.
* **Sidecar freshness enforcement** (a pre-commit drop-in and a CI
  hash check) lands together with the Swift source; the pre-commit
  piece rides the repo-foundation hook chain once the RF sync is in
  place.

### Consequences

* Good, because no codesign infrastructure, cert, notarization, or
  fat binaries are needed, and updating the dialog is a source edit
  rather than a binary re-release.
* Good, because tampered or corrupted sources are refused at
  compile time and the first-run compile is fully visible to the
  user.
* Bad, because the first run is slower and
  xcode-command-line-tools becomes a runtime expectation (an
  acceptable assumption for Homebrew users; the fallback covers the
  rest).
* Bad, because the `.sha256` sidecar is one more file to keep in
  sync (mitigated by the helper script, pre-commit drop-in, and CI
  check).
* Neutral, because compile errors surface at runtime rather than
  install time — mitigated by the fallback chain.

## More Information

This record adapts
[`../migration-investigation/adrs/0001-swift-quit-alert-build-strategy.md`](../migration-investigation/adrs/0001-swift-quit-alert-build-strategy.md)
(now marked superseded by this ADR) to MADR 4.0. The investigation
copy retains the full analysis: option-by-option pros/cons, the
complete `Babble::QuitAlertCompiler` sketch with runtime verification
messages, cache-key derivation, failure-mode handling, and revisit
triggers (Developer-cert acquisition; Homebrew bottle distribution
becoming verified-viable for NSAlert-calling Swift binaries).

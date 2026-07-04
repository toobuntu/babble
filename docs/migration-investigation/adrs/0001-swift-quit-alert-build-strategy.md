<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# ADR-0001: Swift quit_alert build strategy

- **Status:** Superseded by
  [`docs/decisions/0003-swift-quit-alert-build-strategy.md`](../../decisions/0003-swift-quit-alert-build-strategy.md)
  (the MADR 4.0 record in babble's live ADR series; this
  investigation copy retains the full analysis)
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
5. **No `strip(1)`, no `-g` debug-info flag.** The default
   `xcrun swiftc -O` output is already small (~50-100KB for
   a single-NSAlert helper) with minimal debug info.
   Stripping would save a few KB but adds a build step that
   can fail in unexpected ways on Mach-O binaries; the size
   savings don't justify the complexity for a tool of this
   scope. Conversely, explicitly adding `-g` to bake in
   debug info is unnecessary — the helper is stable and
   single-purpose; if it ever misbehaves, the maintainer
   can manually recompile with `-g` for that one debug
   session.

## Safety and transparency design

Auto-compiling user-machine code from a source file the user
did not write themselves is a real trust delegation. The
design below makes the compile **safe** (verifiable; refuses
to compile tampered sources) and **transparent** (visible to
the user; no silent arbitrary code execution).

### Source hash recorded in the repo

A sibling file `swift/src/quit_alert.swift.sha256` is
committed alongside the source. Standard SHA256SUMS format
(`<sha256>  <path>`):

```text
<64-hex-chars>  swift/src/quit_alert.swift
```

This format is verifiable from shell with one command:

```sh
cd <tap_dir>
shasum -a 256 -c swift/src/quit_alert.swift.sha256
```

No Ruby required for the user to confirm the file matches
what's committed in the tap. The recorded hash inherits the
trust model of the tap content itself: GitHub's TLS-protected
delivery via `brew update`, plus (forthcoming) cryptographic
commit signing across the toobuntu org. The planned signing
convention is SSH-based (GPG and x.509 also acceptable as
alternative key types) and is distinct from the DCO-style
`git commit --signoff` currently in use — `--signoff`
records intent metadata but does not cryptographically
authenticate the committer. Cryptographic commit signing
is not yet enabled across toobuntu repos but is planned;
until then, this hash sidecar provides integrity-against-
corruption (catches accidental damage and surfaces
filesystem-level tampering at runtime via
`Babble::QuitAlertCompiler`'s verification step) but no
authentication beyond GitHub's transport and the maintainer's
account credentials.

### Maintenance flow

The .sha256 file gets out of date if `quit_alert.swift`
changes without a corresponding .sha256 update. Three
layers of defense:

1. **Pre-commit hook augmentation** at
   `babble/.githooks/pre-commit.d/01-update-quit-alert-sha256.sh`.
   The canonical pre-commit (synced from repo-foundation)
   iterates `.githooks/pre-commit.d/*` in alphabetical order
   and invokes each executable file in a subprocess — the
   standard per-repo extension point, mirroring `/etc/cron.d`
   and similar Unix drop-in conventions. babble's hook
   regenerates the .sha256 sidecar from the staged content
   of `quit_alert.swift`, runs `scripts/annotate.sh` to add
   the .license sidecar, and stages both. Sketch:

   ```bash
   #!/usr/bin/env bash
   # SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
   #
   # SPDX-License-Identifier: GPL-3.0-or-later
   #
   # Pre-commit drop-in: regenerate quit_alert.swift's SHA256
   # sidecar when the source is staged. Invoked by
   # .githooks/pre-commit (canonical, synced from repo-foundation).

   set -euo pipefail

   main() {
     repo_root="$(git rev-parse --show-toplevel)" || {
       printf '%s\n' "error: not inside a Git work tree" >&2
       exit 1
     }

     cd "$repo_root" || exit 1

     update_quit_alert_sha256
   }

   update_quit_alert_sha256() {
     local source_file="swift/src/quit_alert.swift"
     local sha_file="${source_file}.sha256"

     # Only act when the source is staged in this commit.
     if ! git diff --cached --name-only --diff-filter=ACM \
          | /usr/bin/grep --quiet --line-regexp --fixed-strings -- "${source_file}"; then
       return 0
     fi

     printf '==> Regenerating %s\n' "${sha_file}"

     # Hash the staged content (not the working tree) so partial-
     # staged commits produce a sidecar matching what's actually
     # going into the commit.
     local new_sha
     new_sha=$(git show ":${source_file}" | /usr/bin/shasum --algorithm 256 | /usr/bin/awk '{print $1}')
     printf '%s  %s\n' "${new_sha}" "${source_file}" > "${sha_file}"

     # annotate.sh categorizes .sha256 files into the hash-files
     # category (--force-dot-license), producing a .sha256.license
     # sidecar without modifying the .sha256 file's content.
     if [[ -x scripts/annotate.sh ]]; then
       scripts/annotate.sh
     fi

     git add -- "${sha_file}"
     if [[ -f "${sha_file}.license" ]]; then
       git add -- "${sha_file}.license"
     fi
   }

   main "$@"
   ```

   This hook runs only when `quit_alert.swift` is staged.
   Other commits skip it entirely. The 2-digit `01-` prefix
   establishes the ordering convention for any future
   drop-ins; e.g. `02-some-other-check.sh`.

2. **CI verification** at `.github/workflows/verify-sha256.yml`.
   Runs on every PR and push:

   ```yaml
   - name: Verify quit_alert.swift hash
     run: shasum -a 256 -c swift/src/quit_alert.swift.sha256
   ```

   This is the **enforcement layer**: a PR that modifies the
   .swift file without a matching .sha256 fails CI and can't
   merge. Catches drift even when the local pre-commit hook
   wasn't installed (e.g., contributors who haven't run
   `git config core.hooksPath .githooks`).

3. **Standalone helper script** at
   `scripts/update-quit-alert-sha256.sh`. Manual fallback
   for situations where the pre-commit hook isn't running:
   amending a commit that modified the source, fixing CI
   failures during initial setup, etc.:

   ```sh
   #!/usr/bin/env bash
   set -euo pipefail

   repo_root="$(git rev-parse --show-toplevel)" || {
     printf '%s\n' "error: not inside a Git work tree" >&2
     exit 1
   }

   cd "$repo_root" || exit 1

   source_file="swift/src/quit_alert.swift"
   sha_file="${source_file}.sha256"
   /usr/bin/shasum --algorithm 256 -- "${source_file}" > "${sha_file}"
   echo "Updated ${sha_file}"
   ```

### Runtime verification in Ruby

Before compile, babble computes the actual hash of
`quit_alert.swift` and compares to the recorded value. On
mismatch, **refuse to compile** with a clear error message:

```ruby
# typed: strict
# frozen_string_literal: true

require "digest"

module Babble
  module QuitAlertCompiler
    extend T::Sig

    class << self
      sig { returns(Pathname) }
      def ensure_binary
        verify_source_hash!
        cached_binary_path.tap do |binary|
          compile!(binary) unless binary.exist?
        end
      end

      private

      sig { returns(Pathname) }
      def source_path
        tap_dir/"swift/src/quit_alert.swift"
      end

      sig { returns(Pathname) }
      def sha256_path
        Pathname("#{source_path}.sha256")
      end

      sig { returns(String) }
      def expected_hash
        unless sha256_path.exist?
          odie <<~MSG
            Babble's quit_alert.swift.sha256 file is missing.
            Path: #{sha256_path}
            Run `brew update` to restore the canonical version.
          MSG
        end

        line = sha256_path.read.lines.first
        if line.nil? || line.strip.empty?
          odie <<~MSG
            Babble's quit_alert.swift.sha256 file is empty.
            Path: #{sha256_path}
            Run `brew update` to restore the canonical version.
          MSG
        end

        hex = T.must(line).split(/\s+/, 2).first.to_s
        unless hex.length == 64 && hex =~ /\A[0-9a-f]+\z/
          odie <<~MSG
            Babble's quit_alert.swift.sha256 file is malformed
            (expected SHA256SUMS format with a 64-hex-char hash).
            Path: #{sha256_path}
            Run `brew update` to restore the canonical version.
          MSG
        end

        hex
      end

      sig { returns(String) }
      def actual_hash
        unless source_path.exist?
          odie <<~MSG
            Babble's quit_alert.swift source file is missing.
            Path: #{source_path}
            Run `brew update` to restore the tap.
          MSG
        end

        Digest::SHA256.file(source_path).hexdigest
      end

      sig { void }
      def verify_source_hash!
        expected = expected_hash
        actual = actual_hash
        return if actual == expected

        odie <<~MSG
          Babble refused to compile quit_alert.swift: hash mismatch.

          Expected: #{expected}
          Actual:   #{actual}
          Source:   #{source_path}

          The Swift source file in the babble tap has been modified
          outside the normal commit channel (the recorded hash in
          quit_alert.swift.sha256 doesn't match). To restore the
          canonical version:

            brew update

          If you have local modifications you intend to keep, update
          the recorded hash via:

            scripts/update-quit-alert-sha256.sh

          Babble will not compile a source file whose hash doesn't
          match the recorded value. This protects against accidental
          corruption and unauthorized tampering of the tap.
        MSG
      end

      sig { returns(Pathname) }
      def cached_binary_path
        cache_dir = HOMEBREW_CACHE/"babble"
        arch = Hardware::CPU.arch.to_s
        # Cache key includes a hash prefix so the binary auto-
        # invalidates when the source changes (a new source hash
        # produces a new cache filename; the old binary becomes
        # orphaned and is collected by Homebrew's normal cache
        # rotation).
        cache_dir/"quit_alert_#{arch}_#{actual_hash[0, 12]}"
      end

      sig { params(binary_path: Pathname).void }
      def compile!(binary_path)
        binary_path.parent.mkpath

        ohai "Compiling babble's quit_alert helper (one-time)"
        puts "  Source: #{source_path}"
        puts "  Target: #{binary_path}"
        puts "  SHA256: #{actual_hash} (verified)"
        puts "  Compile: xcrun swiftc -O -o <target> <source>"
        puts
        puts "  This compile happens once per source-hash change;"
        puts "  subsequent runs use the cached binary."

        safe_system "xcrun", "swiftc", "-O",
                    "-o", binary_path.to_s,
                    source_path.to_s
      rescue ErrorDuringExecution
        opoo "xcrun swiftc failed; will use osascript fallback for quit confirmations."
        binary_path.unlink if binary_path.exist?
        raise   # caller catches and switches to osascript path
      end

      sig { returns(Pathname) }
      def tap_dir
        Tap.fetch("toobuntu/babble").path
      end
    end
  end
end
```

### User-visible transparency on first compile

The `ohai` messages above (under `compile!`) print to stderr
on every first compile. The user sees:

```console
==> Compiling babble's quit_alert helper (one-time)
  Source: /opt/homebrew/Library/Taps/toobuntu/homebrew-babble/swift/src/quit_alert.swift
  Target: /Users/<user>/Library/Caches/Homebrew/babble/quit_alert_arm64_a1b2c3d4e5f6
  SHA256: a1b2c3d4...64-hex-chars (verified)
  Compile: xcrun swiftc -O -o <target> <source>

  This compile happens once per source-hash change;
  subsequent runs use the cached binary.
```

The user can:

- Open the source file at the printed path and read the
  Swift source themselves before any compile completes (the
  compile takes ~3-5 seconds; the user has time to Ctrl-C if
  they want to inspect first)
- Run `shasum -a 256 -c swift/src/quit_alert.swift.sha256`
  manually to confirm the verification
- See exactly what command produces the binary

No silent arbitrary code execution.

On subsequent runs (cache hit), no transparency messages
are printed — the binary is treated as established
infrastructure, like any other cached resource. Cache hit
means the source hash matches what the binary was built
from; the verification was performed and passed before the
original compile. If the source changes, the cache key
changes, the cache miss triggers a fresh verification +
compile + transparency message cycle.

### Cache key derivation

The cache filename includes a 12-hex-character prefix of
the source hash:

```text
~/Library/Caches/Homebrew/babble/quit_alert_arm64_a1b2c3d4e5f6
```

Properties:

- **Auto-invalidates** when the source changes: a new hash
  produces a new filename; the binary built from the old
  source becomes orphaned (Homebrew's cache rotation
  eventually removes it)
- **Architecture-specific**: separate cache entries for
  arm64 vs x86_64
- **Unambiguous**: the binary on disk corresponds to a
  specific source-hash + arch combination; impossible to
  accidentally use a binary built from a different source

### Failure mode handling

- **Source-hash mismatch** (verify failure): `odie` with
  the error message above. Babble exits without compiling.
  User must `brew update` (or update the .sha256 file
  manually if they're modifying the source intentionally).
- **Compile failure** (`xcrun swiftc` errors): caught by
  `compile!`'s `rescue ErrorDuringExecution`. Falls
  through to the osascript fallback per the main decision.
- **`.sha256` file missing, empty, or malformed**: `odie`
  with recovery instructions specific to each case.
  `expected_hash` checks for each before attempting to
  parse, so the documented messages fire instead of an
  uncaught Ruby exception.
- **Source file missing**: should never happen (the file
  ships with the tap), but `actual_hash` checks explicitly
  and `odie`s with recovery instructions if it does.

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
- **Compile-time verification**: source hash is checked
  against a committed sidecar before any compile, refusing
  to build tampered sources
- **CI enforcement**: a PR that modifies the .swift file
  without updating the .sha256 sidecar fails CI; drift is
  caught upstream of any user
- **Transparency**: first compile prints source path,
  target path, command, and verified hash; user can
  inspect or interrupt before the compile completes
- **Cache auto-invalidation**: cache key includes the
  source hash, so a source change forces a fresh
  verification + compile cycle

**Bad:**
- First run is slower than no-build cases
- Requires xcode-command-line-tools at runtime
  (acceptable Homebrew-user assumption)
- Compilation errors surface as runtime errors rather than
  install-time errors (mitigation: graceful osascript
  fallback)
- Cache management complexity (small; hash-based)
- **One additional file to keep in sync** (the .sha256
  sidecar). Mitigation: helper script in `scripts/`,
  optional pre-commit augmentation, mandatory CI check.

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
- **Homebrew bottle distribution becomes verified-viable for
  Swift binaries that show NSAlert.** Homebrew bottles are
  built on GitHub Actions runners and ad-hoc signed
  (no Apple Developer cert needed); the install process
  strips the `com.apple.quarantine` xattr. CLI binaries work
  fine via this path. Whether ad-hoc-signed-via-CI Swift
  binaries that call `NSApp`/NSAlert APIs work reliably on
  current macOS (especially macOS 14+ Sonoma's tightened
  Gatekeeper) is open without empirical testing. If a future
  test confirms it works, switching to bottle distribution
  removes the first-run compile latency and the
  xcode-command-line-tools requirement. Until then, the
  auto-compile path is the safe choice.

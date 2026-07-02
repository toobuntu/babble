<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Meta overview

## What was investigated

Babble began as a ksh script (`bbl`) that wrapped `brew update` /
`brew outdated` / `brew upgrade`, plus `mas outdated` /
`mas upgrade`, plus `softwareupdate --list` / `softwareupdate
--install`, into a single interactive routine for the
maintainer's daily macOS updates. Over the course of 2023-2024,
the ksh implementation accumulated ~700 lines of code with
hardcoded app lists, base64-encoded bundle ID export tricks (to
work around shell environment variable limitations), and inline
awk scripts for parsing `brew update` output.

In late 2024 / early 2025, the maintainer began a Ruby rewrite
on a feature branch called `refactor/modular`. The goal: replace
the ksh script with a maintainable Ruby program that:

- Decomposed the monolithic script into logical modules
- Replaced hardcoded app lists with a YAML config file
  (`unified-config.yml`)
- Replaced base64/comma encoding with proper Ruby arrays
- Added a Swift `quit_alert` GUI dialog for unsafe-to-quit casks
- Added retry-on-failure for transient `brew upgrade` failures
- Used JXA (JavaScript for Automation) for cleaner app
  quit/reopen than osascript
- Implemented sophisticated bundle ID resolution via
  `lsregister -dump` parsing

The work spanned over a year and produced ~13,000 lines across
~88 files (much of it in `refactor/ruby/devel/` as design
iterations). It worked, was used as the maintainer's daily
upgrade driver, and accumulated rough edges that the maintainer
intended to polish before merging to main.

## Timeline

- **2023**: Original ksh `bbl` written and refined. Released
  through v0.5.1 (May 2024 ish, last tagged release).
- **2023-2024**: ksh `base64` branch experimented with base64
  encoding of bundle ID arrays for export across subshells.
  Eventually rejected in favor of comma-separated values
  (because bundle IDs cannot contain commas, per Apple's
  CFBundleIdentifier specification). Branch tagged for archival.
- **2024-2025**: `refactor/modular` branch developed the Ruby
  rewrite. Daily use; ~year of polish.
- **2026 February**: GitHub Copilot (Sonnet 4.6) generated PR #1
  (modular rewrite) and PR #3 (terminal exclusion) at the
  maintainer's request. The intent was to see what an
  agent-orchestrated implementation would produce given the
  ksh + refactor/modular as input. Both PRs had quality
  problems and were never iterated on.
- **2026 May**: Maintainer ran `rm -rf babble` against the
  local development copy, mistakenly. Recovery attempts (Time
  Machine, APFS snapshots, FileVault-encrypted block recovery)
  all came up empty. The GitHub remote was the only surviving
  copy.
- **2026 May (this session)**: Planning session that produced
  internal PR reviews
  ([`../reviews/pr1-review.md`](../reviews/pr1-review.md) and
  [`../reviews/pr3-review.md`](../reviews/pr3-review.md)),
  technical-debt register, and the decision to pivot to a
  Homebrew external command implementation. The `refactor/modular`
  branch was rediscovered to contain the maintainer's year+ of
  work (substantively more sophisticated than PR #1), confirming
  the pivot's foundation.

## What survived the pivot

Architectural ideas and code patterns that carry forward into
the external-command rewrite (W3 in master-plan):

- **Module decomposition shape** — orchestrator + cli + brew
  phases + mas phase + macos phase + app lifecycle modules. The
  refactor/modular layout (with module namespacing like
  `MacUtils::BundleLauncher` and `MacOSInterface::DarkMode`)
  cleans up to fit Homebrew's `Homebrew::Cmd::Babble` style.
- **Configuration schema** — YAML with `apps.homebrew[]` and
  `apps.mas[]` arrays, each entry having `token`/`app_id`,
  `bundle_ids`, `unsafe_to_quit`, `quit_message`. Refined in W3
  with split `bundle_ids.{quit_and_reopen, quit_only}` per the
  `unified-config.yml` TODO.
- **Configuration lookup chain** — env override → cwd
  `.babblefile.yml` → project root → XDG → home → /etc.
  Matches Homebrew's own pattern.
- **JXA-based app quit** — replaces osascript -e with JXA for
  proper exception handling and structured output via
  NSFileHandle. refactor/modular's `quit_app` (in
  `brew_upgrade.rb`) is the reference.
- **Swift quit_alert pattern** — use a Swift binary for the
  unsafe-to-quit confirmation dialog with light/dark mode SVG
  icons. Auto-compile via `xcrun swiftc` on first run (per
  PR #1's improvement) because the maintainer has no Apple
  Developer cert and so cannot ship pre-compiled binaries.
  Graceful fallback to `osascript display dialog` if
  xcode-command-line-tools is unavailable.
- **Retry with bootsnap-cache cleanup** — the ksh
  `repeat_command` pattern. Wraps `brew upgrade` invocations
  for transient failures; clears
  `~/Library/Caches/Homebrew/bootsnap` between attempts.
- **Bundle launcher fallback chain** — refactor/modular's
  three-tier (`mdfind` → `lsregister -dump` → walker), to be
  upgraded in W3 to consume the seven-tier helper from
  cask-tools' `purge-quarantine` once it's extracted to
  `Homebrew::CaskTools::BundleDiscovery` (workstream W7).
- **Terminal exclusion design** — env-var-first
  (`TERM_PROGRAM`, `LC_TERMINAL`, `__CFBundleIdentifier`),
  process-tree fallback, allowlist-of-terminal-casks. PR #3's
  attempt was broken (`brew upgrade --except` doesn't exist);
  the design carries forward but the implementation is fresh.
- **Quarantine handling: delegate to `brew purge-quarantine`** —
  cask-tools already ships it; babble doesn't need its own
  parallel implementation. Delegation via tap dependency.
- **Mas v7 JSON migration** — the existing text parsing of
  `mas outdated` becomes `mas outdated --json`. Cleaner;
  bundleID available directly without needing the user to
  configure it.
- **Output formatting** — use Homebrew's `oh1`/`ohai`/`opoo`/
  `ofail` helpers but prefix the message text with the
  `⨀` character. Result: `==> ⨀ Babble message` is visually
  distinct from `==> Brew message`.
- **lsappinfo parsing** — refactor/modular's
  `awk -F'"' '/bundleID/{print $2}' | sort -u` is the working
  pattern (vs. PR #1's broken
  `/CFBundleIdentifier="..."/` regex, which never matched).

## What didn't survive

- **Standalone Gemfile and project Sorbet config** — as an
  external command, babble runs inside Homebrew's Ruby process
  with Homebrew's vendored gems. No project Gemfile.
- **Project-local RuboCop config** — `brew style` provides
  linting via Homebrew's rubocop, matching cask-tools.
- **Bash entry-point portable-Ruby gymnastics** — the
  `bin/babble` Bash wrapper that detects portable Ruby and
  execs it. As an external command, the entry point IS
  `brew babble`. No wrapper needed.
- **Pre-compiled Swift binaries shipped in the repo** —
  refactor/modular's `swift/build/dist/quit_alert_{arm64,x86_64}`
  approach assumed the maintainer could codesign for
  distribution. They cannot (no Apple Developer cert), so
  Gatekeeper would block the binaries on Apple Silicon. PR #1's
  auto-compile-on-first-run is the correct architectural choice.
- **Homemade quarantine purger** — refactor/modular and PR #1
  both had their own. Replaced by delegation to cask-tools'
  `brew purge-quarantine`.

## Why preserve

Three reasons:

1. **Peace of mind for the maintainer.** A year+ of design
   exploration is real intellectual labor. Documenting why
   each decision was made (and which ones got reversed) makes
   that labor durable rather than disposable.
2. **Institutional memory across pivots.** The external-command
   rewrite (W3) will, by definition, throw away the
   refactor/modular code. But the *design ideas* are what
   transfer. This document records them in a form that
   survives the code throwaway.
3. **Rationale visibility for future readers.** When the
   external-command implementation hits a question that the
   refactor/modular work already explored ("why did we land on
   YAML config?", "why JXA over osascript?", "why pre-compile
   the Swift binary then auto-compile then prefer
   auto-compile?"), the answers are here, with code from the
   prior work as evidence.

The prior work is not gone. It's just no longer current.

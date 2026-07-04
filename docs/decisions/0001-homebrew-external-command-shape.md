---
# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

number: 1
title: Homebrew external command shape
status: accepted
date: 2026-07-03
decision-makers:
  - toobuntu
---

# Homebrew external command shape

## Context and Problem Statement

Babble ships as a ksh script (`bbl`, v0.5.2) and has been migrating to
Ruby for over a year. The `refactor/modular` prototype (preserved in
[`../migration-investigation/`](../migration-investigation/)) targeted
a standalone Ruby app: a Bash entry point that bootstraps Homebrew's
portable Ruby, a `lib/babble/` module tree, a project Gemfile,
project RuboCop/Sorbet/RSpec configs. Two externally-authored PRs
(#1, #3) attempted parts of that shape and were closed after review
(see `docs/reviews/`): the toolchain overhead — Ruby bootstrap
gymnastics, dependency vendoring, a parallel lint/typecheck/test
stack — kept swamping the actual upgrade logic.

Meanwhile the sister repo `homebrew-cask-tools` ships working
commands as a Homebrew tap of external commands: no Gemfile, no
project toolchain, Homebrew's own `brew style` / `brew typecheck` /
`brew tests` pipeline, and `brew <command>` as the entry point.

How should the Ruby rewrite be packaged and distributed?

## Decision Drivers

* Babble's runtime dependencies are Homebrew-shaped already: it
  orchestrates `brew update`/`brew upgrade`, and its companion
  `brew purge-quarantine` lives in a tap.
* A year of standalone-app work stalled on toolchain, not logic.
* One maintainer: every parallel toolchain (Bundler, RuboCop config,
  Sorbet setup, RSpec harness, portable-Ruby bootstrap) is permanent
  carrying cost.
* cask-tools proves the external-command shape end to end, including
  CI (hardlink harness) and tap distribution.
* Users already have brew; `brew tap && brew babble` is a smaller ask
  than `git clone` + wrapper script on `$PATH`.

## Considered Options

* **Standalone Ruby app** — `bin/babble` Bash wrapper + portable-Ruby
  bootstrap + `lib/babble/` + project Gemfile/toolchain (the
  pre-pivot plan).
* **Stay on ksh** — keep evolving `bbl`.
* **Homebrew external command in a tap** — `Homebrew::Cmd::Babble` in
  `cmd/babble.rb`, modeled on cask-tools.

## Decision Outcome

Chosen option: **Homebrew external command in a tap**, because babble
runs inside Homebrew's Ruby process with Homebrew's vendored gems and
API, the entire project toolchain collapses into `brew style` /
`brew typecheck` / `brew tests`, and distribution becomes
`brew tap toobuntu/babble`. The GitHub repo is renamed
`toobuntu/babble` → `toobuntu/homebrew-babble` per Homebrew's
tap-naming convention as the *last* gate, at v0.6.0, after
`brew babble` works; GitHub redirects the old name.

The ksh `bbl` stays in the tree as the working daily driver and
rollback path until v0.6.0.

### Consequences

* Good, because there is no Gemfile, no `.bundle/`, no project
  RuboCop/Sorbet/RSpec config, and no `bin/babble` bootstrap — the
  portable-Ruby gymnastics disappear.
* Good, because lint/typecheck/tests are Homebrew's own pipeline,
  identical to cask-tools (specs run via the
  `scripts/run-tests.sh` hardlink harness; see
  [`../architecture.md`](../architecture.md)).
* Good, because babble gains direct access to Homebrew's Ruby API
  (`SystemCommand::Mixin`, `Utils::Output`, `Tap`, JSON of
  `brew outdated`) instead of shelling out for everything.
* Good, because `Homebrew::CaskTools::BundleDiscovery` from the
  cask-tools tap becomes consumable in-process (bundle launcher,
  Block C.3).
* Bad, because babble is coupled to Homebrew internals that are not
  a stable public API; brew upgrades can break it (cask-tools
  carries the same risk, knowingly).
* Bad, because everything runs inside the brew process: no
  standalone binary, and `brew` must be functional for babble to
  run at all (acceptable — babble's whole job is driving brew).
* Neutral, because supporting classes live under `cmd/babble/` in
  the top-level `Babble::*` namespace (brew's tap command discovery
  only scans `cmd/*.rb`; a top-level module cannot shadow brew
  internals the way `Homebrew::Cask` would — see the
  BundleDiscovery namespace note in
  [`../migration-investigation/01-decisions.md`](../migration-investigation/01-decisions.md)).

## More Information

The full investigation — module decomposition, rejected directions,
and the locked design decisions this ADR encodes — is preserved in
[`../migration-investigation/`](../migration-investigation/). The
migration plan is [`../handoff.md`](../handoff.md); the debt register
is [`../technical-debt.md`](../technical-debt.md) (P0.2 tracks the
tap toolchain).

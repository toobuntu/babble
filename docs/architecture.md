<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Architecture

Babble is a Homebrew external command (`brew babble`) distributed as
the `toobuntu/babble` tap, modeled on `homebrew-cask-tools`. This
document describes the target architecture as of Block B (tap
toolchain landed; upgrade logic pending in the C-blocks). The locked
design decisions behind it live in
[`migration-investigation/01-decisions.md`](migration-investigation/01-decisions.md)
and in [`decisions/`](decisions/) (ADRs); the sequencing lives in
[`handoff.md`](handoff.md).

## Entry flow

```text
brew babble [--no-update] [--dry-run]
  └─ brew.rb command dispatch (tap external command, cmd/babble.rb)
       └─ Homebrew::Cmd::Babble < AbstractCommand
            ├─ cmd_args           parses switches into args
            └─ #run               (stub today: ⨀ banner + notice)
                 ├─ Babble::Config.load            (C-blocks)
                 ├─ Babble::AppManager.new(config:)  (C.1)
                 ├─ Babble::BrewUpdate#run           (C.2)
                 ├─ Babble::BrewUpgrade#run          (C.2)
                 ├─ Babble::MasUpgrade#run           (C.6)
                 └─ Babble::MacOSUpdate#run          (C.2+)
```

Babble runs inside Homebrew's Ruby process with Homebrew's vendored
gems and API (ADR
[0001](decisions/0001-homebrew-external-command-shape.md)). There is
no Gemfile, no `bin/babble` wrapper, and no project
RuboCop/Sorbet/RSpec configuration.

## Module structure

Supporting code lives under `cmd/babble/` in the top-level `Babble::*`
namespace: brew's tap command discovery only scans `cmd/*.rb`, so
subtree files cannot become phantom commands, and a top-level module
cannot shadow brew internals the way `Homebrew::Cask` would (see the
BundleDiscovery namespace note in 01-decisions). Classes carry state;
modules are pure utilities — the classification is locked in
01-decisions § "W3 component classification".

| Component | Kind | Lands | Notes |
|-----------|------|-------|-------|
| `Homebrew::Cmd::Babble` | class | **Block B ✓** | entry point; `cmd_args` + `run` |
| `Babble::VERSION` | constant | **Block B ✓** | `cmd/babble/version.rb` |
| `Babble::Formatter` | module | **Block B ✓** | ⨀ output convention (ADR 0002) |
| `Babble::Sh` | module | C.1 | `capture(*cmd)` over `SystemCommand::Mixin` |
| `Babble::AppManager` | class | C.1 | running-app snapshots; quit/reopen lifecycle (P0.3) |
| `Babble::BrewUpdate` | class | C.2 | always-run `brew update` phase (P0.7) |
| `Babble::BrewUpgrade` | class | C.2 | outdated/upgrade phase (P0.5, P0.6); purge-quarantine delegation added in C.4 (P0.8) |
| `Babble::BundleLauncher` | class | C.3 | reopen phase; consumes cask-tools `BundleDiscovery` (P0.4) |
| `Babble::TerminalDetector` | module | C.5 | host-terminal exclusion (P0.9) |
| `Babble::MasUpgrade` | class | C.6 | mas v7 `--json` first (P0.13) |
| `Babble::MacOSUpdate` | class | C.2+ | `softwareupdate` phase |
| `Babble::Config` (+ `Config::{Loader, Validator, Merger, Reorganizer}`) | classes | C.2+ | `AppManager` takes `config:` as `T.untyped` until this lands |
| `Babble::Env` | module | C.2+ | `babble.env` loader (mirrors `brew.env`) |
| `Babble::Retry` | module | P1.3 | retry with bootsnap-cache cleanup |
| `Babble::DarkMode` | module | with the Swift C-block | icon selection for quit_alert (P1.7) |

Phase classes take their collaborators in the constructor
(`app_manager:`, `config:`, `args:`) and expose `#run`; phase-local
state lives in instance variables.

## Output convention (⨀)

All babble-authored output goes through `Babble::Formatter`
(`cmd/babble/formatter.rb`): `oh1`/`ohai`/`opoo`/`ofail` wrappers that
prefix the message with `⨀ ` and delegate to Homebrew's
`Utils::Output::Mixin`, producing e.g. `==> ⨀ Babble message` next to
Homebrew's own `==> …` lines. Severity colors, TTY detection, and
`HOMEBREW_NO_COLOR` come from the stock helpers. Call sites never
hardcode the glyph. Decision record: ADR
[0002](decisions/0002-output-formatting-babble-prefix.md).

## Lint, typecheck, and test pipeline

Babble uses Homebrew's own pipeline, exactly like cask-tools — no
project-local lint or test configuration:

- **Lint** — `brew style --changed` (or explicit paths). Homebrew's
  RuboCop config for Ruby; Homebrew's shfmt/shellcheck dialect for
  shell files, verbatim. The standalone `.shellcheckrc` predates the
  pivot, is superseded by `brew style`, and awaits the post-RF-sync
  cleanup pass (P3.7).
- **Typecheck** — `brew typecheck` (Homebrew's Sorbet) against the
  brew repo with the tap files hardlinked in. Every non-spec file is
  `# typed: strict` with `sig`s on every method; spec files are never
  `typed: strict`. **Local-only for now**: whether the hardlink
  approach lets `brew typecheck` see the tap files on a CI runner is
  unverified (Block B could not test it from the Tier 3 sandbox, and
  the canonical cask-tools workflow ships without a typecheck job).
  Revisit after the first CI runs; until then the enforcement story
  for P0.10 is local runs plus the repo-foundation pre-commit hook
  once the RF sync lands.
- **Tests** — `brew tests --only=…` via
  [`../scripts/run-tests.sh`](../scripts/run-tests.sh). brew only
  discovers specs inside `$(brew --repo)/Library/Homebrew/test/`, so
  the harness temporarily **hardlinks** (not symlinks —
  parallel_rspec's `File.stat` needs targets resolvable inside the
  Homebrew tree) `cmd/babble.rb`, the `cmd/babble/` subtree, and the
  `test/` specs into the brew repo, runs, and unlinks in an EXIT
  trap. The `cmd/babble/` subtree must ride along because the
  hardlinked command resolves `require_relative` against the
  hardlink location. **Do not run `brew update`, `brew upgrade`,
  `brew update-reset`, or git operations inside the brew repo while
  the harness is active.** CI (`.github/workflows/ci.yml`) does the
  same inline: a `style` job (`brew style --changed`) and a
  `brew_tests` job (hardlink → `brew tests --only=cmd/babble` and
  `--only=cmd/babble/formatter` → unlink in an `always()` step),
  both on macos-latest with the Bundler-gems and style caches.
- **License compliance** — SPDX headers via `scripts/annotate.sh`
  (never hand-written); `reuse lint` locally. CI enforcement
  (`lint.yml`: reuse/actionlint/zizmor/shellcheck) arrives via the
  repo-foundation sync, not hand-added (see handoff § Block B).

## Tap layout

```text
babble/                       → renamed toobuntu/homebrew-babble at v0.6.0
├── cmd/
│   ├── babble.rb             the external command (stub → orchestrator)
│   └── babble/               Babble::* support (version, formatter; C-blocks add more)
├── test/
│   └── cmd/                  specs, mirrored onto cmd/ (brew tests layout)
├── scripts/                  run-tests.sh, annotate.sh, sandbox-{enter,exit}.sh
├── docs/                     this file, handoff, technical-debt, decisions/, reviews/
├── swift/                    quit_alert source (+ .sha256 sidecar) — lands in C (ADR 0003)
├── bbl                       ksh daily driver; retired at v0.6.0
└── adrs.toml                 MADR 4.0 via adrs; ADRs in docs/decisions/
```

Install shape at v0.6.0: `brew tap toobuntu/babble`, then
`brew babble`. Until then the dev clone doubles as the installed tap
via a symlink under `$(brew --repository)/Library/Taps/toobuntu/`
(handoff § B.1).

## Bundle discovery (cask-tools dependency)

Babble does not port refactor/modular's three-tier bundle resolver.
The reopen phase (C.3) consumes
`Homebrew::CaskTools::BundleDiscovery` from the `toobuntu/cask-tools`
tap (extracted there by W7): `.new(token, cask_dir)`, `#bundles`,
`#candidate_names`, and the class-level
`BundleDiscovery.lsregister_dump` whose on-disk cache (5-minute TTL)
is shared across consumers. What stays babble-side is the cheap
polling predicate — `osascript -e 'id of app "<bundle-id>"'` — so
`lsregister -dump` (~20 s) never runs inside a polling loop (P0.4).
The quarantine phase similarly delegates to `brew purge-quarantine`
(P0.8) instead of shipping its own purger. Note the namespace:
`Homebrew::CaskTools`, **not** `Homebrew::Cask` — defining
`Homebrew::Cask` would shadow `::Cask` for brew code inside
`module Homebrew` and break brew at runtime.

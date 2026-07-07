<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Migration investigation — babble Ruby port (2024-2026)

This directory preserves the year-plus of investigation and
implementation work that preceded the babble pivot to a Homebrew
external command. It exists because the work informed the
architectural choices of the eventual rewrite, and so the rationale
remains visible after the pivot rewrites the code.

## How to read this

If you only read one file, read [`00-meta-overview.md`](00-meta-overview.md)
— it summarizes what was investigated, what survived the pivot
into the external-command shape, and what was rejected.

For specific topics:

- [`01-decisions.md`](01-decisions.md) — the architectural
  decisions made, organized by topic
- [`02-rejected-directions.md`](02-rejected-directions.md) —
  what was considered and discarded, with rationale
- [`03-known-bugs-and-rough-edges.md`](03-known-bugs-and-rough-edges.md)
  — issues identified during refactor/modular's year of use,
  for the external-command rewrite to address
- [`modules/*.md`](modules/) — per-module discussion of the
  refactor/modular implementation, what survives the pivot, and
  what doesn't
- [`adrs/`](adrs/) — Architecture Decision Records relevant to
  the Ruby port; some may carry forward (not duplicated) into
  the external-command repo
- [`/stash/`](../../stash/) — extracted source files
  preserved in full, organized by source. Lives at the repo
  top level rather than under `docs/` because it's preserved
  code, not documentation. Subdirectories: `pre-refactor/`,
  `refactor-modular/`, `base64/`, `pr1/`.

## Sources

This investigation drew from four primary sources:

1. **`refactor/modular` branch** (the year-plus of work). The
   maintainer's design exploration that survived a local
   `rm -rf` because the most recent state was on the GitHub
   remote. This is the **primary source** for design ideas
   carrying forward to the external-command rewrite.
2. **Pre-refactor archive** (`archive/babble/ruby/lib/` and
   `archive/babble/ruby/rubytest/`). Earlier design iterations
   that predate refactor/modular's modular layout. Different
   class shapes (`AppManager`, `ConfigManager` as classes), a
   battery-detection helper using IOKit, and eight
   iterations of the upgrade-casks logic in `rubytest-upgrade_casks-v{2..8}.rb`.
   Some ideas (config-file merging via `deep_merge`,
   battery-aware upgrade gating) didn't make it into
   refactor/modular but are worth preserving as design
   inspiration.
3. **`base64` branch** (an earlier ksh approach to bundle ID
   storage via base64 encoding). Superseded by simpler
   comma-separated values when bundle IDs were determined
   incompatible with commas. The `NOTES.txt` from this branch
   contains valuable knowledge about lsappinfo parsing,
   base64-vs-NUL-vs-comma tradeoffs, and several `INSERTION/Unused`
   code snippets worth preserving.
4. **PR review docs** (`docs/reviews/pr1-review.md` and
   `docs/reviews/pr3-review.md`). These document the GitHub
   Copilot (Sonnet 4.6) attempts — both fundamentally flawed
   relative to the year+ of refactor/modular work. The Copilot
   branches were discarded; the reviews remain canonical
   documentation of what was wrong.

## Tagged branches

Two archive tags preserve the source branches:

- `archive/<DATE>-ruby-refactor-modular` — the year+ of work
- `archive/<DATE>-ksh-base64` — the base64 ksh approach with notes

Browse the tags at https://github.com/toobuntu/homebrew-babble/tags
(the repo was renamed from toobuntu/babble in W3; GitHub redirects).

## Status

- The work this directory preserves is **archived**. The active
  babble migration plan lives in [`../handoff.md`](../handoff.md).
- The technical debt register lives in
  [`../technical-debt.md`](../technical-debt.md).
- The external-command rewrite is workstream W3 in
  `~/devel/claude/desktop/workspace/master-plan.md`.

<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Documentation index

Internal-only documentation for the babble project.

## Active

- [`handoff.md`](handoff.md) — what comes next: Block A (sanity, ship
  v0.5.2, branch hygiene), Block B (conventions stack), Block C (P0
  blockers). Includes Claude Code handoff prompts.
- [`tech-debt.md`](tech-debt.md) — prioritized debt register (P0–P3)
- [`reviews/pr1-review.md`](reviews/pr1-review.md) — internal review of
  PR #1 (Ruby modular rewrite)
- [`reviews/pr3-review.md`](reviews/pr3-review.md) — internal review of
  PR #3 (terminal exclusion)

## Conventions

Docs in this directory follow the patterns used in sibling repos
`homebrew-cask-tools/docs/` and `blackoutd/docs/`:

- Markdown with REUSE/SPDX headers
- ADRs in `decisions/` numbered `0001-…`, `0002-…`
- Reviews in `reviews/` named after their PR (`pr<N>-review.md`)
- en_US spelling
- Prose paragraphs preferred over deeply nested bullet lists

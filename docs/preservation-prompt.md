<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Claude Code prompt — babble preservation (W2)

Copy everything between the `>>>` markers into Claude Code. This
runs at Tier 3 (fresh-clone-no-remote sandbox), launched from
inside `~/devel/claude/desktop/toobuntu/babble/` after running
`./scripts/sandbox-enter.sh --mode=no-remote`.

>>>

I am running the babble migration investigation archive (W2).
Two phases:

**Phase 1: Branch triage and cleanup.** Read each WIP branch on
the babble GitHub remote, decide whether it has any salvageable
diff worth landing on main, and either consolidate the work or
mark the branch for archive. Goal: smaller archive surface (fewer
tags), with any genuinely useful diffs from dead branches captured
on main pre-tag.

**Phase 2: Preservation.** Build the
`docs/migration-investigation/` directory of prose +
code-archive material. Cross-link from babble's existing docs.
Output the list of `git tag` commands the maintainer runs after
the PR merges.

The work informs but does NOT execute the W3 external-command
pivot. No bug fixes in PR #1 Ruby code. No attempt to land a
working pre-pivot Ruby version. The release path stays: ksh v0.5.2
(current main) → external command v0.6.0 (W3).

I am running this session at Tier 3 (fresh-clone-no-remote).

## Read first (in order)

1. `AGENTS.md` and `docs/agent-principles.md` — already loaded by
   session start; re-read with intent
2. `~/devel/claude/desktop/workspace/master-plan.md` (W2 in
   particular)
3. `docs/preservation-actions.md` — context for this session
4. `docs/handoff.md` — the per-repo migration plan being preserved
5. `docs/technical-debt.md` — the priorities being preserved
6. `docs/reviews/pr1-review.md` — already-written PR review
7. `docs/reviews/pr3-review.md` — already-written PR review
8. The pre-`rm -rf` prototype: every file under
   `archive/babble/ruby/refactor/ruby/` (read all, list any
   you don't have access to)
9. `archive/_usr_local_bin_bbl` — the saved Bash entry point
10. `bbl` — the canonical ksh script being phased out

For PR #1 contents: use `git show
origin/copilot/rewrite-babble-as-ruby-app:lib/babble/<file>` to
read what's on that branch.

For PR #3 contents: similarly via
`origin/copilot/fix-terminal-upgrade-issue`.

For older WIP: `origin/refactor/modular` and `origin/base64`.
Read what's on each.

## Decisions already locked

- **Two-phase work**: triage cleanup, then preservation.
- **No pre-pivot Ruby fixes.** Don't try to make Ruby work.
- **Repository for preservation:** `babble/docs/migration-investigation/`.
- **Branch tagging dates use `$(date -j +%Y-%m-%d)`** at execution
  time, NOT placeholder dates.
- **License:** GPL-3.0-or-later. SPDX headers via
  `scripts/annotate.sh`.

## Cut a feature branch

```sh
git switch -c preservation-archive
```

Land work in commits you propose for approval.

## Phase 1: Branch triage

For each WIP branch on the babble remote, do the following:

1. Read the branch contents and what it differs from main on:
   ```sh
   git log --oneline main..origin/<branch>
   git diff --stat main...origin/<branch>
   ```
2. Categorize:
   - **Archive**: branch contains substantial work that informed
     the migration but isn't worth landing on main (e.g., PR #1
     itself, PR #3). Plan: tag at archive time with
     `archive/${TODAY}-<topic>`.
   - **Consolidate**: branch contains a small, genuinely useful
     diff against main that is independent of the migration work
     (e.g., a typo fix, a minor refactor that's still relevant
     under the external-command shape). Plan: cherry-pick onto
     this preservation branch, no separate archive tag needed.
   - **Discard**: branch is stale (heavily behind main, content
     superseded by something else, exploratory dead-end). Plan:
     no archive tag; the maintainer deletes the branch after
     this PR merges.

   Branches to evaluate:
   - `origin/copilot/rewrite-babble-as-ruby-app` (PR #1 — Ruby
     modular rewrite)
   - `origin/copilot/fix-terminal-upgrade-issue` (PR #3 —
     terminal exclusion attempt)
   - `origin/refactor/modular` (3 commits ahead, 2 behind main —
     older modular-refactor WIP)
   - `origin/base64` (4 commits ahead, 33 behind main — older
     experiment)
   - any other branches present

3. Output a triage summary block in your final report. Format:

   ```
   ## Branch triage outcome

   | Branch | Status | Rationale | Action |
   |--------|--------|-----------|--------|
   | copilot/rewrite-babble-as-ruby-app | Archive | PR #1; the migration archive's primary subject | Tag archive/${TODAY}-pr1-rewrite |
   | copilot/fix-terminal-upgrade-issue | Archive | PR #3; terminal-detector design preserved separately | Tag archive/${TODAY}-pr3-terminal |
   | refactor/modular | <decision> | <why> | <action> |
   | base64 | <decision> | <why> | <action> |
   ```

4. For "Consolidate" branches: cherry-pick the relevant commits
   onto this preservation branch. Each cherry-pick gets its own
   commit. Note any conflicts and resolution.

5. For "Discard" branches: note them in the triage table but
   take no git action (the maintainer deletes after the PR
   merges).

The maintainer will review your triage decisions specifically
before approving the PR. If any decision feels wrong, the
maintainer pushes back and you revise.

## Phase 2: Preservation

After triage, build `docs/migration-investigation/`. Structure:

```
docs/migration-investigation/
├── README.md
├── 00-meta-overview.md
├── 01-decisions.md
├── 02-rejected-directions.md
├── modules/
│   ├── orchestrator.md
│   ├── brew-upgrade.md
│   ├── mas-upgrade.md
│   ├── macos-update.md
│   ├── app-manager.md
│   ├── bundle-launcher.md
│   ├── waiter.md
│   ├── config-manager.md
│   ├── quarantine-purger.md
│   ├── terminal-detector.md
│   └── retry.md
├── adrs/
│   └── 0001-swift-quit-alert-build-strategy.md
└── code-archive/
    ├── README.md
    ├── prototype/
    │   ├── brew_cask_utils.rb
    │   ├── brew_update.rb
    │   ├── brew_upgrade.rb
    │   ├── macos_updates.rb
    │   ├── running_gui_bundle_ids.rb
    │   ├── mas_token_generator.rb
    │   ├── dark_mode.rb
    │   ├── display_alert.rb
    │   └── ... (all .rb files from archive/babble/ruby/refactor/ruby/lib/)
    ├── pr1/
    │   ├── orchestrator.rb
    │   ├── cli.rb
    │   ├── brew_upgrade.rb
    │   ├── mas_upgrade.rb
    │   ├── macos_update.rb
    │   ├── app_manager.rb
    │   ├── bundle_launcher.rb
    │   ├── config_manager.rb
    │   ├── waiter.rb
    │   ├── quarantine_purger.rb
    │   ├── constants.rb
    │   ├── babble       (the bin/babble Bash wrapper)
    │   └── quit_alert.swift
    └── pr3/
        └── bbl-terminal-detector-attempt.diff   (the diff PR #3 attempted)
```

### Write README.md

`docs/migration-investigation/README.md`:

```markdown
# Migration investigation — babble Ruby port (2024-2026)

This directory preserves the year-plus of investigation and
implementation work that preceded the babble pivot to a Homebrew
external command. It exists because the work informed the
architectural choices of the eventual rewrite, and the team
wants the rationale visible after the pivot rewrites the code.

## How to read this

If you only read one file, read [`00-meta-overview.md`](00-meta-overview.md)
— it summarizes what was investigated, what survived the pivot
into the external-command shape, and what was rejected.

For specific topics:

- `01-decisions.md` — the architectural decisions made,
  organized by topic
- `02-rejected-directions.md` — what was considered and
  discarded, with rationale
- `modules/*.md` — per-module discussion of the prototype +
  PR #1 + the surviving design ideas
- `adrs/*.md` — Architecture Decision Records relevant to the
  Ruby port; carried over (not duplicated) into the
  external-command repo
- `code-archive/` — extracted source files preserved as-was, in
  full, organized by source (prototype, PR #1, PR #3)

## Status

- The work this directory preserves is **archived**. The active
  babble migration plan lives in `../handoff.md`.
- The technical debt register lives in `../technical-debt.md`.
- Branches associated with this work are tagged
  `archive/YYYY-MM-DD-<topic>` and visible at
  https://github.com/toobuntu/homebrew-babble/tags
```

### Write 00-meta-overview.md

Executive summary. Sections:

- **Origin**: how the Ruby port started; the maintainer's goal
  of consistent code style and exploring agent-orchestrator
  capabilities
- **Timeline**: rough phases of investigation (early prototyping
  in `archive/babble/ruby/`, PR #1 in early 2026, PR #3 mid-2026,
  the planning session that produced reviews and tech-debt, the
  external-command pivot decision)
- **What survived the pivot**: short list of patterns/ideas that
  carry forward to the external-command rewrite (module
  decomposition shape, Swift `quit_alert` strategy, terminal
  detector design, configuration lookup chain, etc.)
- **What didn't survive**: the standalone Gemfile, project-local
  RuboCop, Bash entry-point gymnastics, etc.
- **Why preserve**: rationale for this directory existing —
  peace-of-mind for the maintainer; future readers seeing the
  reasoning; institutional memory across pivots

Aim for ~500-700 words.

### Write 01-decisions.md

Consolidated architectural decisions, with code blocks. Sections:

- **Module decomposition**: the orchestrator/cli/brew/mas/macos/app
  split with rationale (mirrors ksh's phase boundaries; enables
  per-phase testing). Code from `lib/babble.rb` (PR #1) and the
  prototype's split.
- **Configuration schema**: `apps.homebrew[]` and `apps.mas[]`
  arrays with `bundle_ids`/`unsafe_to_quit`/`quit_message`. Code:
  the example `config/apps.yml` from PR #1.
- **Configuration lookup chain**: env → cwd → repo root → XDG →
  home → /etc. Rationale: matches Homebrew's own pattern.
- **Bash entry point pattern**: portable-Ruby resolution via
  `$(brew --repository)/Library/Homebrew/vendor/portable-ruby/current/bin/ruby`,
  with `brew vendor-install ruby` as bootstrap.
- **Swift quit_alert auto-compile strategy**: rationale (no
  Apple Developer cert), the auto-compile-on-first-run mechanism,
  light/dark mode SVG icon strategy. References ADR
  `adrs/0001-swift-quit-alert-build-strategy.md`.
- **App lifecycle: quit → upgrade → reopen**: the three-phase
  pattern with confirmation dialog for unsafe-to-quit casks.
- **Terminal exclusion design**: env-var-first detection
  (`TERM_PROGRAM`, `LC_TERMINAL`, `__CFBundleIdentifier`),
  process-tree fallback, allowlist-of-terminal-casks.
- **Quarantine handling: delegate to brew purge-quarantine**.
  Decision: don't ship a competing implementation.
- **Mas v7 JSON migration**: the move from text parsing to
  `mas list/outdated --json`.
- **Retry-on-failure with bootsnap-cache cleanup**: the ksh
  `repeat_command` pattern carried forward.
- **Logging and subprocess wrappers**: `Babble::Log` and
  `Babble::Sh` modules.
- **Sorbet `# typed: strict`**: typing discipline decision.
- **REUSE/SPDX compliance via `scripts/annotate.sh`**: license
  hygiene.

For each decision, 2-3 sentences of rationale plus a code block
of the relevant pattern. Code blocks come from the actual files
(prototype or PR #1) — extract verbatim, don't paraphrase.

Aim for ~3000-5000 words.

### Write 02-rejected-directions.md

What was considered and dropped. Sections:

- **Standalone library with project Gemfile**: the original
  Ruby-port plan; rejected when external-command became viable.
- **`brew bundle` as upgrade orchestrator**: investigated.
  Rejected because brew bundle is declarative-state-only (no
  quit/reopen lifecycle), provides no bundle ID mapping for
  apps, doesn't surface the visual feedback babble's interactive
  workflow needs.
- **`brew typecheck` for babble's library**: rejected because
  it's private API limited to Homebrew/brew. Babble uses
  `bundle exec srb tc` (standalone) or, post-W3, Homebrew's
  internal Sorbet (external command).
- **Project-local RuboCop**: rejected in favor of `brew style`,
  matching cask-tools.
- **Shipping a pre-built Swift quit_alert binary**: rejected
  because no Apple Developer cert means Gatekeeper would block
  it. Auto-compile-on-first-run wins.
- **A custom formatter for "babble said this" vs. Homebrew said
  this**: considered. Decision: use Homebrew's existing
  `oh1`/`ohai`/`opoo`/`ofail` helpers and prefix the message
  with the `⨀` character. Result: `==> ⨀ Babble message` is
  visually distinct from `==> Brew message`. Adopt in W3.
- **`brew bundle dump` for installed-app discovery**: rejected
  in favor of using brew's Ruby APIs directly
  (`Formula.installed`, `Cask::Caskroom.casks`) once external
  command is available.

For each, give the rationale for considering it and the rationale
for rejecting. Code blocks where helpful.

Aim for ~1500-2500 words.

### Write modules/*.md (one per module)

Template each follows:

```markdown
# <Module name>

## Purpose

<1-2 paragraphs: what this module did or was meant to do>

## Prototype implementation (`archive/babble/ruby/refactor/ruby/lib/<file>`)

<paragraph + code block of the prototype>

## PR #1 implementation (`origin/copilot/rewrite-babble-as-ruby-app:lib/babble/<file>`)

<paragraph + code block of PR #1's version>

## Design ideas that survive the pivot

<bulleted or prose: what carries forward to the external-command rewrite>

## Design ideas that don't survive

<bulleted or prose: what gets discarded or reshaped>

## Bugs / blockers found

<reference to docs/reviews/pr1-review.md by section ID; don't duplicate the reviews>
```

Use this template for: orchestrator, brew_upgrade, mas_upgrade,
macos_update, app_manager, bundle_launcher, waiter, config_manager,
quarantine_purger, terminal_detector (no implementation; design
only), retry (no implementation; ksh-only ancestor).

If a module has no prototype and no PR #1 implementation (e.g.,
terminal_detector), say so and document the design intent only.

### Write adrs/0001-swift-quit-alert-build-strategy.md

Full ADR per cask-tools/blackoutd format. Sections: Context,
Decision Drivers, Considered Options, Decision Outcome,
Consequences. Content covered in `docs/handoff.md` § P1.9.

This is the only ADR being written in W2. The external-command
rewrite (W3) will likely add more ADRs to a separate
`docs/decisions/` (not under `migration-investigation/`).

### Populate code-archive/

- `code-archive/README.md` — index of what's where; cite source
  paths.
- `code-archive/prototype/` — copy every `.rb` file from
  `archive/babble/ruby/refactor/ruby/lib/` (and subdirs) into
  this flat-ish layout. If there are subdirs in the source
  (`utils/`, `macos_interface/`), flatten with prefixes
  (`utils-running_gui_bundle_ids.rb`,
  `macos_interface-dark_mode.rb`).
- `code-archive/pr1/` — extract every `lib/babble/*.rb` and
  `bin/babble` and `swift/src/quit_alert.swift` from
  `origin/copilot/rewrite-babble-as-ruby-app` via `git show`.
  Save with original names.
- `code-archive/pr3/` — extract the ksh `bbl` diff from
  `origin/copilot/fix-terminal-upgrade-issue` (save as a
  `.diff` file rather than the full ksh script, since most of
  the file is identical to main).

These are *full* extracts, not summaries. Files preserve their
original SPDX headers (or get headers added via annotate.sh if
absent).

## Run scripts/annotate.sh

```sh
bash scripts/annotate.sh
reuse lint
```

If `LICENSES/GPL-3.0-or-later.txt` doesn't exist, create via
`reuse download GPL-3.0-or-later`.

## Compute and report tag commands

After triage and preservation, list the surviving (Archive-status)
branches and write the tag commands the maintainer will run after
PR merge. Use `$(date -j +%Y-%m-%d)` with command substitution
intact in the output.

Example output to include in the final report:

```sh
TODAY=$(date -j +%Y-%m-%d)

git tag --sign --annotate "archive/${TODAY}-pr1-rewrite" \
  --message "..." origin/copilot/rewrite-babble-as-ruby-app
git tag --sign --annotate "archive/${TODAY}-pr3-terminal" \
  --message "..." origin/copilot/fix-terminal-upgrade-issue

git push origin --tags
```

Adjust per actual triage outcome — only Archive-status branches
get tags.

## Cross-link from existing files

Add references from:

- `docs/handoff.md` — add a one-line pointer near the top:
  "For preservation of pre-pivot work, see
  `docs/migration-investigation/`"
- `docs/technical-debt.md` — same pointer in the document header

## PR conventions and end-of-session protocol

PR conventions (org-wide):

- First commit-message line ≤ 50 characters
- All commits signed off (`git commit --signoff`)
- en_US spelling
- Long options
- SPDX headers via `scripts/annotate.sh`, never hand-written

End-of-session protocol (Tier 3, no remote):

When done:

1. Confirm `reuse lint` passes locally.
2. Confirm all commits are on the `preservation-archive` branch
   with user-approved messages.
3. Confirm `docs/migration-investigation/` is complete: README,
   00-meta, 01-decisions, 02-rejected, modules/*, adrs/*,
   code-archive/* all populated.
4. Output a final report:
   - **Branch triage outcome** as a table (per the template
     above)
   - Branch name (preservation-archive)
   - Commit count and subjects (including any consolidate
     cherry-picks)
   - File list (with size hints; this PR will be large because
     of code-archive)
   - Known issues if any
   - The exact branch-tag commands for the maintainer to run
     post-merge (using `$(date -j +%Y-%m-%d)`)
   - The exact procedure for the user to run from the primary
     checkout to push and open the PR
5. Do not push or open a PR yourself.

## What NOT to do

- Don't fix bugs in PR #1 or PR #3 code. Just preserve.
- Don't try to land a working pre-pivot Ruby version.
- Don't modify `bbl` (the ksh script).
- Don't touch any of the user's other repos
  (blackoutd, homebrew-cask-tools, brew, etc.) beyond reading
  `~/devel/claude/desktop/toobuntu/blackoutd/scripts/` for the
  annotate.sh and sandbox-enter.sh sources if they aren't
  already in babble's scripts/.
- Don't touch `docs/handoff.md` or `docs/technical-debt.md`
  except for the one-line cross-reference pointer in each.
- Don't push to GitHub or open PRs.

>>>

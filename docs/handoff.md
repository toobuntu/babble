<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Handoff — what comes next

> **For preservation of pre-pivot work**, see
> [`migration-investigation/`](migration-investigation/) — the year+ of
> `refactor/modular` work and rationale for the external-command
> pivot.

This is the action document for the work that follows the planning
session that produced [`technical-debt.md`](technical-debt.md),
[`reviews/pr1-review.md`](reviews/pr1-review.md), and
[`reviews/pr3-review.md`](reviews/pr3-review.md). It is sequenced so
each block can be done in isolation, with clear stop-and-decide gates
between blocks.

> **Nomenclature note.** This file references `technical-debt.md`
> (full word) per the consistency decision recorded after Block A.
> If the file currently on disk is named `tech-debt.md` (the babble
> shipping name as of this session), Block A.2 includes a `git mv`.

The blocks are:

1. **Block A — Sanity, ship v0.5.2, branch hygiene.** Manual; no
   Claude Code. ~30–45 min.
2. **Block 0 — Scaffold the Claude Code config on the new clone.**
   Manual; no Claude Code (this is the prerequisite for *any* Claude
   Code session). ~30–45 min.
3. **Block B — Set up the Ruby toolchain on `ruby-migration`.**
   Claude Code handoff prompt at the end of this block. **Run at
   Tier 3.** ~1–2 sessions.
4. **Block C — Address P0 blockers in dependency order.** Claude
   Code handoff prompt for each blocker; sequence matters. **Tier
   varies (mostly Tier 3); see § Tier guidance below.** ~3–5
   sessions.

Block C only starts after Block B's PR is merged and you've done a
manual smoke pass. Don't try to fold C into B — the toolchain stack
is its own deliverable and reviewing both at once will be exhausting.

## Lint and typecheck strategy

Babble uses Homebrew's lint pipeline directly:

- **`brew style <files>`** for lint. Same rubocop config as Homebrew
  internals and cask-tools. No project-local `.rubocop.yml`; no
  rubocop entry in the Gemfile.
- **`bundle exec srb tc`** for typecheck. `brew typecheck` is private
  API limited to the Homebrew/brew repo, so it can't run on babble's
  `lib/`. The Gemfile has minimal Sorbet entries (`sorbet`,
  `sorbet-runtime`); same Sorbet version brew uses, just invoked
  through Bundler.
- **`bundle exec rspec`** for tests.

This matches cask-tools' style (`brew style --changed` in CI; heavy
Sorbet usage with `# typed: strict` headers and `sig { ... }` everywhere)
while accommodating babble's library layout (cask-tools links its `cmd/*.rb`
into `$(brew --repo)/Library/Homebrew/cmd/` for CI; babble can't do
that with `lib/babble/`).

## Preconditions

### Machine-level Claude Code config

Before any Claude Code session on any project (not just babble), the
maintainer's machine needs:

- `~/.claude/CLAUDE.md` — copied from the canonical baseline
- `~/.claude/settings.json` — copied from the canonical baseline

The canonical baseline for these files is currently at
`~/devel/claude/desktop/_claude-config-baseline/global/`. The
`scaffolding/` repo is intended to take over this role but its
`global/` subdirectory hasn't been populated yet (see
`scaffolding/README.md` for the target state). When `scaffolding/`
lands its global templates, this section should be updated to point
there.

If the global config isn't in place yet, follow the one-time setup
instructions in `_claude-config-baseline/README.md` § "Initial setup
(one-time, per machine)" before continuing.

### Tier guidance (per blackoutd ADR 0007)

Each Claude Code session in this plan runs at one of the four
isolation tiers defined in
`~/devel/claude/desktop/blackoutd/docs/decisions/0007-layered-isolation-strategy.md`.
Read the ADR if you haven't recently. Short summary:

- **Tier 1** — Primary checkout, in-host Seatbelt + permission rules.
  Routine work, single feature, single PR, low `excludedCommands`
  fire rate.
- **Tier 2** — In-tree worktree under `worktrees/`. Workflow
  isolation only (not security). For testing scripts that mutate the
  repo without dirtying the primary checkout.
- **Tier 3** — Fresh-clone-no-remote sandbox via
  `scripts/sandbox-enter.sh --mode=no-remote`. Workspace + remote
  isolation. **For sessions that fire `excludedCommands` more than
  ~3 times** (any session creating multiple commits, or using `gh`
  more than once or twice), or autonomous multi-commit work.
- **Tier 4** — Lume macOS VM with Claude Code IN the VM. For
  Mythos-class threats, Mach IPC testing, overnight autonomous
  runs.

Per-block tier recommendations:

| Block | Tier | Rationale |
|-------|------|-----------|
| Block A | n/a | Manual; no Claude Code session |
| Block 0 | n/a | Manual; no Claude Code session |
| Block B | **3** | Multi-commit (~10–20 commits expected), heavy `gh` use to open PR; far exceeds the ~3-fire threshold |
| Block C.1 | **3** | Multi-commit + `gh pr create`; same reasoning |
| Block C.2–C.6 | **3** | Same shape as C.1 |
| Block C.7 (sweep) | **3** | Largest of the C-blocks; broadest file changes; max `gh` fire rate |

Tier 1 doesn't appear in the C plan because every C-block creates a
PR. Tier 4 doesn't appear because babble doesn't use Mach IPC and
the work isn't adversarial-capability-tier.

The `sandbox-enter.sh` script lives in
`~/devel/claude/desktop/blackoutd/scripts/sandbox-enter.sh` (it
hasn't been promoted to `scaffolding/scripts/` yet). Copy it into
`babble-ruby/scripts/` during Block 0 so it's in place when Block B
starts.

---

## Block A — Sanity, ship v0.5.2, branch hygiene (do today)

Manual work; no agent involvement. The goal is to get the repo into
a clean, known state before we start serious migration work.

### A.1 — Verify what landed in this session

Before anything else, confirm the planning artifacts are in place
and the prompt-text scrub worked:

```sh
cd ~/devel/claude/desktop/babble
ls -la docs/                   # README.md, handoff.md, tech-debt.md (or technical-debt.md), decisions/, reviews/
ls -la docs/reviews/           # pr1-review.md, pr3-review.md
ls -la archive/                # _OPENING_PROMPT.txt, _usr_local_bin_bbl, babble/
cat .gitignore | head --lines 10  # confirm /OPENING_PROMPT.txt and /archive/_OPENING_PROMPT.txt are listed
git status --short             # untracked: docs/, .gitignore, archive/_OPENING_PROMPT.txt, possibly handoff.md.[01]
```

Expected: all files present, `.gitignore` correctly excludes the
prompt artifact.

### A.2 — Rename `tech-debt.md` → `technical-debt.md` (org-wide consistency)

The decision recorded after the planning session was to standardize
on `technical-debt.md` (full word) across all repos. Babble's file
currently ships as `docs/tech-debt.md`; rename now while it's still
unreferenced by external links:

```sh
cd ~/devel/claude/desktop/babble
git mv docs/tech-debt.md docs/technical-debt.md

# Update the cross-references in handoff.md and README.md
# (do these in your editor; sed -i differs between BSD and GNU)
# - docs/handoff.md: 3 references
# - docs/README.md: 1 reference
```

Verify: `grep --extended-regexp 'tech-debt\.md' docs/` should show
no remaining matches after the edits. (A reference to "the
tech-debt register" in prose without the `.md` extension is fine.)

> Note for later: `homebrew-cask-tools/docs/tech-debt.md` is the
> other repo using the short form. Add a low-priority issue there
> to rename it; not in scope for this babble session.

### A.3 — Decide: commit the planning artifacts to `main`?

The session produced these pieces of content:

| File | Content | Recommendation |
|------|---------|----------------|
| `.gitignore` | New file | **Commit** |
| `docs/README.md` | New file | **Commit** |
| `docs/handoff.md` | New file (this file) | **Commit** |
| `docs/technical-debt.md` | New file (renamed) | **Commit** |
| `docs/handoff.md.0`, `docs/handoff.md.1` | Working copies | **Don't commit; delete** |
| `docs/reviews/pr*-review.md` | New files | **Commit** |
| `archive/_OPENING_PROMPT.txt` | Personal artifact | **Don't commit** (gitignored) |

The internal reviews are written for one reader (you) — but they're
also the audit trail for why the Ruby migration looks the way it
does, and they belong with the code. Commit them on `main`.

```sh
cd ~/devel/claude/desktop/babble

# Clean up the working copies of this file
rm docs/handoff.md.0 docs/handoff.md.1

git switch main
git add .gitignore docs/
git status                      # confirm only .gitignore and docs/ are staged
git diff --cached               # quick scan
git commit --signoff -m "Add planning docs and tech debt register" -m "$(cat <<'EOF'
- docs/handoff.md: blocked plan for the Ruby migration
- docs/technical-debt.md: P0-P3 register covering legacy ksh,
  Ruby migration, and greenfield gaps
- docs/reviews/pr1-review.md: internal review of #1
- docs/reviews/pr3-review.md: internal review of #3
- .gitignore: scaffolding for the upcoming migration
EOF
)"
```

The 50-char first-line limit applies — "Add planning docs and tech
debt register" is 41 chars; verify with
`git log -1 --format=%s | awk '{print length}'`.

### A.4 — Tag and release v0.5.2 from main

The diff between v0.5.1 and main is the two-line `print` statement
addition. Cut the release.

```sh
git log v0.5.1..HEAD --oneline             # confirm what's in
script/log-since-latest-tag                 # human-readable view
script/release-notes                        # writes Markdown to pasteboard
git tag --sign --annotate v0.5.2 --message "Babble v0.5.2"
git push origin main v0.5.2
gh release create v0.5.2 --title "v0.5.2" --notes "$(pbpaste)"
```

This discharges the small ksh-side debt and gives a stable fallback
release. **It also lets you close PRs #1 and #3 without leaving
users on a stale tag.**

### A.5 — Close PR #1 and PR #3 with disposition comments

Both PRs are being discarded in favor of a fresh `ruby-migration`
branch. Close (don't merge) with brief comments referencing the
review docs.

For PR #1:

```sh
gh pr comment 1 --body "$(cat <<'EOF'
Closing in favor of a fresh re-implementation on a new
`ruby-migration` branch cut from `main`. The architecture and Bash
entry-point shape are keepers; the Ruby implementation has issues
that aren't tractable as incremental fixes — see internal review at
docs/reviews/pr1-review.md (committed on main) for the breakdown.

Branch left in place as a reference. Salvageable pieces will be
cherry-picked onto `ruby-migration` per the path-forward section of
the review.
EOF
)"
gh pr close 1
```

For PR #3:

```sh
gh pr comment 3 --body "$(cat <<'EOF'
Closing without merging. Implementation has a fatal bug
(`brew upgrade --except` is not a real flag) and the rebase onto
PR #1 the description claims was never persisted to remote. The
terminal-detection idea is sound and will be re-implemented in
`lib/babble/terminal_detector.rb` once the Ruby migration cleanup
is in place. See docs/reviews/pr3-review.md for the analysis. Issue
#2 stays open and will be closed by the new implementation.
EOF
)"
gh pr close 3
```

Don't delete the branches — the PR-1 branch in particular is a
useful reference while we're cherry-picking.

### A.6 — Tear down read-only worktrees; create a clean Ruby-migration clone

The worktrees from the planning session were for reading PR
branches side-by-side. Block B onward will be active development
with Claude Code, and the isolation of a separate clone is worth
the disk per our earlier discussion.

```sh
# Tear down the planning-session worktrees
cd ~/devel/claude/desktop/babble
git worktree list               # confirm the 4 worktrees
git worktree remove ../babble-pr1
git worktree remove ../babble-pr3
git worktree remove ../babble-refactor-modular
git worktree remove ../babble-base64
git worktree prune              # clean up administrative entries
ls ../                          # confirm only `babble` remains under desktop/

# Make a fresh full clone for the Ruby migration work.
# This goes in ~/devel/claude/desktop/ so Filesystem MCP can reach it.
cd ~/devel/claude/desktop
git clone https://github.com/toobuntu/babble.git babble-ruby
cd babble-ruby
git switch -c ruby-migration
git push -u origin ruby-migration
```

The original `~/devel/claude/desktop/babble/` clone now serves as
the "main / released versions" reference. The new
`~/devel/claude/desktop/babble-ruby/` clone is where Ruby migration
work happens. Two physical clones, two mental boxes.

### A.7 — Add the GitHub branch protection ruleset

There's no scaffolding-repo guidance for this yet (it's a tech-debt
item on the scaffolding repo, noted at the bottom of this doc).
Until that exists, configure manually for `ruby-migration` and
`main`:

```sh
# Verify current ruleset state
gh api /repos/toobuntu/babble/rulesets

# Or browse: https://github.com/toobuntu/babble/settings/rules
```

Suggested rules for `main`:
- Require PR before merge
- Require ≥ 1 review approval (waived in practice for solo
  maintainer; keep enabled but use admin override sparingly)
- Require status checks to pass: `style`, `rspec` (these will exist
  after Block B)
- Require linear history (matches the no-rebase-on-merge convention
  by forbidding rebase merges; merge commits are still fine)
- Require signed commits (matches the `git commit --signoff` +
  signed tag convention)
- Block force pushes
- Block deletions

Suggested rules for `ruby-migration`:
- Require PR before merge (forces the C-blocks through review)
- Status checks: `style`, `rspec`
- Block force pushes
- Allow rebase, squash, or merge commits (less strict than `main`
  since this is the migration branch)

GitHub's UI for rulesets is at Settings → Rules → Rulesets → New
ruleset. Set the target ref pattern (`refs/heads/main` and a
separate `refs/heads/ruby-migration` ruleset).

### A.8 — Stop and decide

Stop here and confirm the following before starting Block 0:

- [ ] v0.5.2 tag published, release notes posted
- [ ] PRs #1 and #3 closed with disposition comments
- [ ] `tech-debt.md` renamed to `technical-debt.md`; cross-refs
      updated
- [ ] Branch protection rulesets configured for `main` and
      `ruby-migration`
- [ ] Worktrees torn down; `babble-ruby/` full clone exists with
      `ruby-migration` branch checked out and pushed
- [ ] `archive/_OPENING_PROMPT.txt` is local-only (not pushed)
- [ ] You're ready to commit ~30–45 minutes to manual scaffolding
      setup

If anything's unclear, pause and ask before Block 0.

---

## Block 0 — Scaffold the Claude Code config on `ruby-migration`

This block is **manual, no Claude Code**. Its purpose is to land
the project-level Claude Code scaffolding (`AGENTS.md`, `CLAUDE.md`,
`docs/agent-principles.md`, `.claude/settings.json`, plus the
sandbox tier scripts) so that any Claude Code session afterwards
starts with the project's guard rails in effect.

This has to happen before Block B because Block B *is* a Claude
Code session, and we don't want that session running without the
scaffolding in effect.

The procedure follows `scaffolding/docs/usage.md`, with file
locations adjusted because most templates are still in
`_claude-config-baseline/` (the scaffolding repo's `project/`
subdirectory hasn't been populated yet — see scaffolding tech-debt
items at the end of this file).

### 0.1 — Copy the templates

Working in `~/devel/claude/desktop/babble-ruby/` on the
`ruby-migration` branch:

```sh
cd ~/devel/claude/desktop/babble-ruby
git switch ruby-migration

# Source paths — adjust if/when scaffolding/project/ gets populated
B=~/devel/claude/desktop/_claude-config-baseline
BD=~/devel/claude/desktop/blackoutd

# Per-repo Claude Code config
mkdir -p .claude scripts
cp "$B/project/settings.json"            .claude/settings.json
cp "$B/project/AGENTS.md"                AGENTS.md
cp "$B/project/docs/agent-principles.md" docs/agent-principles.md

# CLAUDE.md as the thin Homebrew-pattern pointer
cat > CLAUDE.md <<'EOF'
@AGENTS.md
EOF
cat > CLAUDE.md.license <<'EOF'
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
EOF

# Sandbox tier scripts (Tier 3 minimum; copy Tier 4 too in case
# we need it later)
cp "$BD/scripts/sandbox-enter.sh"        scripts/sandbox-enter.sh
cp "$BD/scripts/sandbox-exit.sh"         scripts/sandbox-exit.sh
cp "$BD/scripts/sandbox-vm-enter.sh"     scripts/sandbox-vm-enter.sh
cp "$BD/scripts/sandbox-vm-exit.sh"      scripts/sandbox-vm-exit.sh
cp "$BD/scripts/sandbox-vm-bootstrap.sh" scripts/sandbox-vm-bootstrap.sh
chmod +x scripts/*.sh
```

### 0.2 — Adapt `AGENTS.md` for babble

Open `AGENTS.md` and edit the placeholder content. Below is a
suggested shape — fill in details I don't know.

In the SPDX header at the top:

```
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
SPDX-License-Identifier: GPL-3.0-or-later
```

In the title:

```
# AGENTS.md — babble
```

In the project summary:

```
Babble is an interactive upgrade routine for Homebrew (formulae and
casks), Mac App Store apps via mas, and macOS system updates via
softwareupdate. Currently shipping as a ksh script (bbl, v0.5.2);
in active migration to a modular Ruby application with a Bash
wrapper for portable-Ruby bootstrap. Target platform: macOS 14+ on
Apple Silicon and Intel.
```

In "Key constraints":

```
- Target: macOS 14+ (Sonoma); macOS 15+ for Swift binary (Swift 5.9
  syntax requires Xcode 15)
- Architecture: arm64 and x86_64 (Universal-binary capable)
- Runtime: Homebrew's vendored portable Ruby (current stable)
- Dependencies: brew (required), mas (optional), Xcode Command
  Line Tools (required for the Swift quit_alert auto-compile)
- Codesigning: ad-hoc only (no Apple Developer cert; see
  docs/decisions/0001-swift-quit-alert-build-strategy.md)
- License: GPL-3.0-or-later (single license)
- Lint: `brew style <files>` (Homebrew rubocop config; no
  project-local .rubocop.yml)
- Typecheck: `bundle exec srb tc` (Sorbet via Bundler;
  `brew typecheck` is private API limited to Homebrew/brew)
```

Strip the "Build and lint" placeholder section entirely for now —
fill it in during Block B once the toolchain lands.

In "Architecture", point at `docs/architecture.md` (which Block B
will create) rather than enumerating modules inline.

In "Project-specific tools", note:

```
- bbl (the ksh script) — DO NOT run. It performs real upgrades that
  affect the user's installed software. Always require explicit
  approval if a session has reason to invoke it.
- bin/babble (when it exists, post-Block-C) — same restriction.
- osascript -e 'quit app id "..."' — quits running user apps.
  Always ask before invoking.
- xcrun swiftc — used to auto-compile the Swift quit_alert binary
  on first run. Output is written to swift/build/ inside the
  project tree; sandbox-allowed.
```

In "Open work", point at `docs/technical-debt.md` and note that
ROADMAP.md and CONTRIBUTING.md are tracked items not yet present.

In "Documents to read on first load", **edit the list** to match
babble's actual filenames:

```markdown
For non-trivial work:

1. `docs/agent-principles.md` — universal operating principles
   (also imported above)
2. `docs/technical-debt.md` — current priorities and known issues
3. `docs/handoff.md` — current block-by-block plan
4. `docs/decisions/` — accepted ADRs (when present)

For PR work specifically, also:

- `docs/reviews/` — internal PR reviews (when present)
```

### 0.3 — Adapt `.claude/settings.json` for babble

The baseline template has placeholder strings (the ones starting
with `//`) in `permissions.allow`, `permissions.ask`, and
`sandbox.excludedCommands`. Replace them with babble's actual
rules.

Open `.claude/settings.json` and replace the contents with the
following. This is the babble-specific settings, layered on top of
your `~/.claude/settings.json` global baseline:

```jsonc
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",

  "permissions": {
    "allow": [
      "Bash(brew style)",
      "Bash(brew style:*)",
      "Bash(brew style --changed)",
      "Bash(bundle exec srb tc)",
      "Bash(bundle exec srb tc:*)",
      "Bash(bundle exec rspec:*)",
      "Bash(script/style)",
      "Bash(script/style:*)",
      "Bash(script/syntax)",
      "Bash(script/syntax:*)",
      "Bash(script/log-since-latest-tag)",
      "Bash(script/release-notes)",
      "Bash(brew --prefix)",
      "Bash(brew --repository)",
      "Bash(brew --caskroom)",
      "Bash(brew --version)",
      "Bash(brew commands:*)",
      "Bash(brew config)",
      "Bash(brew outdated:*)",
      "Bash(brew info:*)",
      "Bash(brew list:*)",
      "Bash(brew desc:*)",
      "Bash(mas version)",
      "Bash(mas list:*)",
      "Bash(mas outdated:*)",
      "Bash(mas info:*)",
      "Bash(softwareupdate --list:*)",
      "Bash(/usr/bin/lsappinfo list)",
      "Bash(/usr/bin/lsappinfo info:*)",
      "Bash(lsappinfo list)",
      "Bash(lsappinfo info:*)",
      "Bash(xcrun --find swiftc)",
      "Bash(xcrun --find swift)"
    ],

    "ask": [
      "Bash(./bbl)",
      "Bash(bbl)",
      "Bash(./bin/babble)",
      "Bash(bin/babble)",
      "Bash(brew update)",
      "Bash(brew update:*)",
      "Bash(brew install-bundler-gems)",
      "Bash(osascript -e:*)",
      "Bash(osascript -l JavaScript:*)",
      "Bash(/usr/bin/osascript:*)",
      "Bash(/usr/bin/open:*)",
      "Bash(open -b:*)",
      "Bash(open -g:*)",
      "Bash(scripts/annotate.sh:*)",
      "Bash(scripts/sandbox-enter.sh:*)",
      "Bash(scripts/sandbox-exit.sh:*)",
      "Bash(xcrun swiftc:*)"
    ]
  },

  "sandbox": {
    "excludedCommands": [
      "/usr/bin/osascript:*",
      "osascript:*",
      "/usr/bin/open:*",
      "open:*",
      "xcrun swiftc:*",
      "bundle install"
    ]
  },

  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "if [ \"$(git -C \"${CLAUDE_PROJECT_DIR:-.}\" branch --show-current)\" = \"main\" ]; then echo 'Direct edits to main are not allowed. Create a feature branch (git switch -c c-NN-<topic>) before editing.' >&2; exit 2; fi",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

Notes:

- `brew style` is allowed because it's read-only (rubocop). The
  `--changed`, `--fix`, etc. variants all match the `brew style:*`
  pattern.
- `bundle exec srb tc` and `bundle exec rspec` are allowed because
  they're read-only diagnostics.
- `brew install-bundler-gems` is in `ask` because it modifies
  Homebrew's gem state. Block B's `bin/setup` calls it once.
- `excludedCommands` uses the `:*` suffix per ADR 0005 / 0007 — the
  `bare command` and `space-asterisk` forms are buggy. Each entry
  is treated as a partial sandbox bypass primitive (per #45113);
  this is part of why these blocks run at Tier 3.
- `xcrun swiftc:*` is in `ask` *and* `excludedCommands`. The `ask`
  forces approval; `excludedCommands` lets the compile escape the
  project-tree write restriction (Swift's intermediate output
  sometimes lands in `$TMPDIR`).
- The main-branch edit guard hook uses branch naming
  `c-NN-<topic>` to match the C-block convention.

### 0.4 — Adapt `docs/agent-principles.md` (probably no edits)

Open `docs/agent-principles.md` and skim. The baseline file is
intentionally written to apply to *any* of your projects, so most
of it is exactly right for babble. If anything in the file needs
project-specific override, the *override* goes in `AGENTS.md`
(which is loaded *after* the imported principles file, so it can
override). Don't edit `docs/agent-principles.md` unless the change
applies to all your repos — in which case update the canonical at
`_claude-config-baseline/project/docs/agent-principles.md` (or its
eventual home in `scaffolding/`) first, then re-copy.

### 0.5 — Add tech-debt entries (CONTRIBUTING.md, scaffolding follow-ups)

Append the following to `docs/technical-debt.md` under § P2 —
Architectural / quality, after section P2.8:

```markdown
### P2.9 — `CONTRIBUTING.md` for human contributors

Babble currently has no `CONTRIBUTING.md`. The agent-instruction
files (`AGENTS.md`, `docs/agent-principles.md`) are oriented at
agents but a thin contributor guide for humans is missing.

Org-wide conventions (en_US spelling, 50-char commit subjects,
`git commit --signoff`, modern git verbs) belong in
`dot-github/profile/CONTRIBUTING.md`, not duplicated here. Adding
that file to dot-github is a separate follow-up worth opening on
that repo.

**Acceptance criteria:**

- [ ] `CONTRIBUTING.md` at repo root, repo-specific content only
- [ ] Lists license (`GPL-3.0-or-later`)
- [ ] Documents `bin/setup` for dev deps
- [ ] Documents lint command (`brew style --changed`) and test
      command (`bundle exec rspec`)
- [ ] Documents how to enable githooks
      (`git config core.hooksPath .githooks`)
- [ ] Points at `https://github.com/toobuntu/.github` for org-wide
      conventions; does NOT duplicate them
- [ ] Points at `AGENTS.md` for AI agent conventions and
      `docs/agent-principles.md` for the operating principles
- [ ] References `docs/handoff.md` for current migration state

**Files:** `CONTRIBUTING.md`.

### P2.10 — Add babble's branch-protection ruleset to scaffolding

Babble's branch protection rules were configured manually in Block
A.7. The `scaffolding/` repo's bootstrap docs should document this
step so future bootstraps don't have to re-derive the right rules.

This is a follow-up on the `scaffolding/` repo, not on babble.
Tracked here so it doesn't get lost.

**Acceptance criteria (on scaffolding repo):**

- [ ] `scaffolding/docs/usage.md` adds a "Step N — branch
      protection" section
- [ ] Recommends a `refs/heads/main` ruleset and a
      `refs/heads/<feature-branch>` ruleset
- [ ] Provides a `gh api` command pattern for setting them up
- [ ] Links to GitHub's ruleset documentation

**Files:** `~/devel/claude/desktop/scaffolding/docs/usage.md`.

### P2.11 — Consolidate scaffolding repos

`_claude-config-baseline/` and `scaffolding/` both exist and both
are incomplete; this duplication is confusing. Migrate everything
to `scaffolding/` (the more polished home) and decommission
`_claude-config-baseline/`.

This is a follow-up on the `scaffolding/` repo, not on babble.
The babble Block 0 instructions can be updated to use
`scaffolding/project/` paths once the consolidation completes.

**Acceptance criteria (on scaffolding repo):**

- [ ] `scaffolding/global/{CLAUDE.md, settings.json}` populated
      from `_claude-config-baseline/global/`
- [ ] `scaffolding/project/{AGENTS.md, CLAUDE.md, settings.json,
      adrs.toml}` populated from `_claude-config-baseline/project/`
      and template authoring
- [ ] `scaffolding/project/docs/agent-principles.md` populated
      from canonical
- [ ] `scaffolding/project/githooks/pre-commit` populated from
      blackoutd
- [ ] `scaffolding/project/workflows/*.yml` populated from
      blackoutd
- [ ] `scaffolding/project/ISSUE_TEMPLATE/` populated from
      `dot-github/ISSUE_TEMPLATE/`
- [ ] `scaffolding/scripts/{annotate.sh,
      rewrite-pr-as-merge-commit.sh, sandbox-*.sh}` populated
      from blackoutd
- [ ] `_claude-config-baseline/` decommissioned (replaced with a
      single README pointer)
- [ ] `sync-principles.sh` reruns against each consumer repo

**Files:** the scaffolding repo (whole).
```

This is a small edit to the existing `docs/technical-debt.md`.
Filesystem MCP overwrites the whole file, so do this in your
editor of choice. Or, defer this edit until Block B's session
when Claude Code can be asked to make the change as part of the
toolchain commit.

### 0.6 — Verify the scaffolding and commit

```sh
# Verify file structure
ls -la AGENTS.md CLAUDE.md CLAUDE.md.license
ls -la .claude/settings.json
ls -la docs/agent-principles.md
ls -la scripts/sandbox-*.sh

# Validate JSON syntax
jq empty .claude/settings.json && echo OK

# Validate Markdown imports work syntactically
grep --extended-regexp '^@docs/agent-principles\.md' AGENTS.md \
  && echo "Import line found"
[ -f docs/agent-principles.md ] && echo "Import target found"

# License sidecar for the JSON file (JSON doesn't support comments)
cat > .claude/settings.json.license <<'EOF'
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
EOF

# Commit
git add AGENTS.md CLAUDE.md CLAUDE.md.license docs/agent-principles.md \
        .claude/ scripts/
git status                                  # confirm what's staged
git diff --cached --stat                    # quick review
git commit --signoff -m "Add Claude Code project scaffolding" -m "$(cat <<'EOF'
Set up the project-level Claude Code config and sandbox scripts:

- AGENTS.md: project-specific agent context, imports the
  operating principles via @docs/agent-principles.md
- CLAUDE.md: thin pointer to AGENTS.md (Homebrew pattern)
- docs/agent-principles.md: universal operating principles
  copied from canonical baseline
- .claude/settings.json: babble-specific allow/ask/excluded
  rules, main-branch edit guard hook
- scripts/sandbox-*.sh: Tier 3 and Tier 4 isolation scripts
  copied from blackoutd

Layered on top of ~/.claude/settings.json, which provides the
universal sandbox config and denies. See blackoutd ADR 0005 and
0007 for the architecture rationale.
EOF
)"
git push origin ruby-migration
```

The commit message subject is "Add Claude Code project scaffolding"
(38 chars). Verify with the same `awk '{print length}'` trick.

### 0.7 — Stop and decide

Stop here and confirm before starting Block B:

- [ ] `AGENTS.md` reads correctly when you read it through. Project
      summary, key constraints, "Documents to read on first load"
      list all match babble.
- [ ] `.claude/settings.json` parses as valid JSON (`jq empty`
      passes)
- [ ] You can imagine reading the AGENTS.md from the perspective of
      Claude Code on its first session and finding nothing
      surprising
- [ ] The sandbox scripts are present and executable
- [ ] `git push` succeeded; CI on the `ruby-migration` branch is
      either green or gracefully not-yet-configured (we haven't
      added workflows yet, so "no checks" is fine)

If anything's unclear or you want to adjust the AGENTS.md
language, do that now.

---

## Block B — Set up the Ruby toolchain on `ruby-migration`

Block 0 has landed the agent-instruction scaffolding. This block
adds the *Ruby toolchain* — Gemfile, Sorbet, RSpec, brew-style
lint, REUSE, githooks, CI workflows, architecture docs, the first
ADR. The result is a branch that can run `bundle exec rspec`,
`bundle exec srb tc`, `brew style --changed`, `reuse lint`, and
`actionlint` cleanly — but doesn't actually do anything yet,
because we haven't ported any logic.

This is **P0.2** in [`technical-debt.md`](technical-debt.md),
revised to exclude the agent scaffolding (which Block 0 already
handled).

### B.1 — Pre-flight (manual, before launching Claude Code)

A few decisions need to be locked before Claude Code starts,
because they shape the structure and aren't worth iterating on:

1. **Dual license or single?** Babble stays single
   (GPL-3.0-or-later). It's an end-user tool, not a library; the
   dual-license rationale (encouraging upstream contribution to
   Homebrew) doesn't apply.

2. **macOS version floor.** Per Block 0's AGENTS.md edits: macOS
   14+ for general use; macOS 15+ for the Swift binary because
   Swift 5.9 syntax requires Xcode 15.

3. **Lint via `brew style`, not project-local rubocop.** `brew
   style <files>` works on arbitrary Ruby files and uses Homebrew's
   rubocop config — same as cask-tools. No project-local
   `.rubocop.yml`; no rubocop entry in the Gemfile. CI runs
   `brew style` instead of `bundle exec rubocop`.

4. **Sorbet via Bundler.** `brew typecheck` is private API limited
   to Homebrew/brew, so it can't run on babble. The Gemfile
   includes `sorbet` (development group) and `sorbet-runtime`
   (default group). `# typed: strict` for `lib/babble/*.rb`;
   `# typed: false` for `spec/**/*.rb` (RSpec metaprogramming
   doesn't play well with strict Sorbet).

5. **Skill files (`.claude/skills/`)**: defer to a later session
   after Block C lands a few P0s — the skills are easier to
   write once the workflows they encode have been done a few
   times.

Lock these answers before launching Claude Code, or be prepared
to re-answer them mid-session.

### B.2 — Enter Tier 3 sandbox before launching Claude Code

Block B is multi-commit work that will fire `excludedCommands`
many times (every `git commit`, every `gh` invocation). Per ADR
0007's escalation triggers, run at Tier 3:

```sh
cd ~/devel/claude/desktop/babble-ruby
./scripts/sandbox-enter.sh --mode=no-remote
# This creates a fresh clone with no remote configured. The script
# prints the sandbox path and may launch a sub-shell or print a
# `cd <path>` instruction; follow whichever it does.
```

Verify the sandbox is set up correctly:

```sh
# Inside the sandbox clone:
git remote -v       # should be empty (no remote)
git status          # should show ruby-migration branch
ls -la .claude/     # should have settings.json from Block 0
```

Then launch Claude Code from inside the sandbox clone.

### B.3 — Claude Code handoff prompt for Block B

Copy-paste the following into Claude Code:

> I am setting up the Ruby toolchain for the babble project. Block 0
> already landed the Claude Code project scaffolding (`AGENTS.md`,
> `CLAUDE.md`, `docs/agent-principles.md`, `.claude/settings.json`,
> sandbox scripts). I am running this session at Tier 3
> (fresh-clone-no-remote). The reference repos to model on are
> `~/devel/claude/desktop/homebrew-cask-tools/` and
> `~/devel/claude/desktop/blackoutd/`.
>
> Read these documents first, in order:
>
> 1. `AGENTS.md` (project context — already loaded by your session
>    start, but re-read with intent)
> 2. `docs/agent-principles.md` (operating principles — also already
>    loaded; the pre-action discipline section governs everything
>    below)
> 3. `docs/handoff.md` (this file's parent context; § Block B is
>    your scope)
> 4. `docs/technical-debt.md` (P0.2 in particular — but note: agent
>    scaffolding part of P0.2 is already done; you're landing the
>    Ruby-toolchain part)
> 5. `docs/reviews/pr1-review.md` (the rationale for why this
>    branch exists)
> 6. `~/devel/claude/desktop/homebrew-cask-tools/.github/workflows/ci.yml`
>    (the canonical model for `brew style` + `brew install-bundler-gems`
>    in CI)
> 7. `~/devel/claude/desktop/homebrew-cask-tools/cmd/purge-quarantine.rb`
>    (the canonical model for Sorbet sigs and `T.let`/`T.unsafe`
>    patterns)
> 8. `~/devel/claude/desktop/blackoutd/Gemfile` (template for a
>    minimal Gemfile)
>
> Decisions already locked (do not re-litigate):
>
> - License: GPL-3.0-or-later, single license (not dual)
> - macOS floor: 14 (Sonoma); macOS 15 (Sequoia) for Swift binary
> - Lint: `brew style` (no project-local rubocop)
> - Typecheck: `bundle exec srb tc` (`brew typecheck` is private
>   API for the Homebrew/brew repo only)
> - Sorbet: `# typed: strict` for `lib/babble/*.rb`,
>   `# typed: false` for `spec/**/*.rb`
> - Claude skill files: defer to a later session
>
> Cut a feature branch off `ruby-migration` named
> `b1-ruby-toolchain` and land the following in commits that you
> propose for approval:
>
> **Ruby tooling.**
>
> - `Gemfile` and `Gemfile.lock` — minimal:
>   - `gem "sorbet-runtime"` (default group)
>   - `gem "sorbet", group: :development`
>   - `gem "rspec", "~> 3.13"` (default group; needed at runtime by
>     specs, but in practice grouped to development is also fine)
>   - `gem "simplecov", group: :development`
>
>   NO rubocop. NO `homebrew-rubocop` config. `brew style` provides
>   linting via Homebrew's rubocop, matching cask-tools' approach.
>
> - `.bundle/config` with `BUNDLE_PATH: vendor/bundle` and
>   `BUNDLE_DISABLE_SHARED_GEMS: true` per the Bundler hygiene rule
>   in `docs/agent-principles.md`.
>
> - `bin/setup` script (mark `+x`):
>   1. `bundle install`
>   2. `bundle exec srb init` if `sorbet/` doesn't exist
>   3. `brew install-bundler-gems` (so `brew style` is ready)
>
> - `.rspec` with default formatter and `--require spec_helper`.
>
> - `sorbet/config` configured for `lib/`. Run `bundle exec srb
>   init` yourself to bootstrap `sorbet/rbi/*` and commit those.
>
> - **Do NOT create `.rubocop.yml`.** `brew style` uses Homebrew's
>   rubocop config; we don't override it.
>
> **REUSE / licensing.**
>
> - `LICENSES/GPL-3.0-or-later.txt` populated via
>   `reuse download GPL-3.0-or-later`.
> - `scripts/annotate.sh` adapted from
>   `homebrew-cask-tools/scripts/annotate.sh` — preserve the
>   special-case for generated files.
> - Add SPDX headers to all existing files in the repo that don't
>   already have them: `bbl`, `script/*`, `assets/*.svg`,
>   `archive/_usr_local_bin_bbl`, `LICENSE`, `README.md`,
>   `.shellcheckrc`, `.gitignore`, `.github/dependabot.yml`,
>   `.github/workflows/tests.yml`. (`docs/*.md` and the Block-0
>   scaffolding files already have headers.)
> - Run `reuse lint` and confirm a clean exit before committing.
>
> **Pre-commit hook.**
>
> - `.githooks/pre-commit` running on changed files:
>   - `brew style --changed` for Ruby
>   - `bundle exec srb tc` for Ruby (typecheck)
>   - `shfmt -d` and `shellcheck` for Bash
>   - `reuse lint --quiet`
>
>   Bash script, not a framework like `pre-commit-hooks`. Mark
>   `+x`. Match the cask-tools and blackoutd shape.
> - The new CONTRIBUTING.md (below) documents enabling it via
>   `git config core.hooksPath .githooks`.
>
> **CONTRIBUTING.md** (per P2.9 in tech-debt). Repo-specific only:
>
> - License (GPL-3.0-or-later)
> - `bin/setup` for dev deps
> - Lint: `brew style --changed`. Test: `bundle exec rspec`.
> - Enable githooks: `git config core.hooksPath .githooks`
> - Points at `https://github.com/toobuntu/.github` for org-wide
>   conventions (en_US spelling, 50-char commit subject, signed
>   commits, modern git verbs, etc.). DO NOT duplicate those rules
>   here.
> - Points at `AGENTS.md` for AI agent conventions and
>   `docs/agent-principles.md` for the operating principles.
> - References `docs/handoff.md` for current migration state.
>
> **CI workflows.** Replace the existing
> `.github/workflows/tests.yml` with:
>
> - `ci.yml` — modeled after cask-tools' `ci.yml`. Two jobs on
>   `macos-latest`:
>   - `style` — set up Homebrew via
>     `Homebrew/actions/setup-homebrew@main`, cache the bundler
>     gems and the brew style cache as cask-tools does, run
>     `brew install-bundler-gems`, then `brew style --changed`,
>     then `bundle exec srb tc`
>   - `rspec` — set up Homebrew, `bundle install` (vendor/bundle
>     via `.bundle/config`), `bundle exec rspec spec/`. Note: no
>     specs yet; will exit 0 until C.1 lands the first.
> - `lint.yml` — Ubuntu runner: `reuse lint`, `actionlint` (use
>   `rhysd/actionlint` action), `shfmt -d`, `shellcheck` for the
>   remaining Bash. The cheap stuff that doesn't need Homebrew.
> - Update `.github/dependabot.yml` to include `bundler` ecosystem
>   alongside `github-actions`, both grouped to minimize PR noise.
>
> **Architecture doc skeleton.**
>
> - `docs/architecture.md` with sections: "Overview", "Module
>   structure" (placeholder; modules will be filled in by Block C),
>   "Entry flow" (Bash → portable Ruby → Ruby orchestrator),
>   "Configuration resolution" (cite the lookup chain from P1.4 in
>   technical-debt), "Subprocess strategy", "macOS compatibility"
>   (cite `docs/agent-principles.md`), "Why a Bash wrapper at all"
>   (Homebrew env bootstrapping rationale), "Lint and typecheck"
>   (brief: `brew style` for lint, `bundle exec srb tc` for
>   typecheck, why not `brew typecheck`), "Regenerating the demo
>   SVG" (placeholder for P3.2).
> - `docs/decisions/0001-swift-quit-alert-build-strategy.md` —
>   write this one out fully. Rationale (no Apple Developer cert,
>   so no codesign, so can't ship a pre-built binary). Tradeoffs
>   (requires xcode-command-line-tools at runtime; first run is
>   slower; no notarization). Failure modes (no toolchain → fall
>   back to `osascript display dialog` per P1.8). Trigger for
>   revisiting (acquiring an Apple Developer cert, or moving to a
>   notarized installer pipeline). Format: cask-tools / blackoutd
>   ADR style.
>
> **README updates.**
>
> - Note the migration is in progress.
> - Point at v0.5.2 for the released ksh version.
> - Link to docs/.
>
> **What NOT to do in this session.** Do NOT touch any of:
>
> - `bbl` (the ksh script — leave it as-is for the migration to
>   delete later)
> - `lib/babble/*` (no logic ports yet — that's Block C)
> - `bin/babble` (will be ported in Block C with the simplified
>   Ruby bootstrap from P1.1)
> - `swift/src/quit_alert.swift` (Block C)
> - `config/apps.yml` (Block C; per P1.4 it'll move out of the
>   repo)
> - `AGENTS.md`, `CLAUDE.md`, `docs/agent-principles.md`,
>   `.claude/settings.json` (already in place from Block 0; don't
>   re-litigate)
> - `scripts/sandbox-*.sh` (already in place from Block 0)
> - `.rubocop.yml` (we're not creating one — see "Ruby tooling"
>   above)
>
> The result of this session is a branch that has scaffolding,
> tooling, CI, and architecture docs in place but is otherwise
> functionally identical to main. `bbl` should still run;
> `bin/babble` should not yet exist.
>
> **PR conventions** (org-wide rules per
> `https://github.com/toobuntu/.github` and the operating
> principles):
>
> - First commit-message line ≤ 50 characters
> - All commits signed off (`git commit --signoff`)
> - en_US spelling throughout
> - Use long options (`grep --extended-regexp`, etc.)
> - Don't hand-write SPDX headers — run `scripts/annotate.sh`
>
> **Important — Tier 3 context and end-of-session protocol.**
>
> This session runs at Tier 3 (fresh-clone-no-remote). The clone
> has no `origin` remote — `git push` will fail. You don't have
> permission to push or open PRs anyway (`git push` is universally
> denied; `gh pr create` requires user approval).
>
> When the work is done:
>
> 1. Confirm `brew style --changed`, `bundle exec srb tc`,
>    `bundle exec rspec` (zero examples), `reuse lint`,
>    `actionlint`, `shfmt -d`, `shellcheck` all pass locally.
> 2. Confirm all your commits are on the `b1-ruby-toolchain`
>    branch with the user-approved messages.
> 3. Output a final report: branch name, commit count and subjects,
>    summary of what landed and what was deferred (with rationale),
>    known issues if any, and the exact procedure the user should
>    follow to push and open the PR FROM THE PRIMARY CHECKOUT (not
>    this sandbox clone). The procedure is roughly:
>
>    ```sh
>    # In the primary checkout (~/devel/claude/desktop/babble-ruby):
>    git fetch <sandbox-path>/.git b1-ruby-toolchain:b1-ruby-toolchain
>    git switch b1-ruby-toolchain
>    git push origin b1-ruby-toolchain
>    gh pr create --draft --base ruby-migration \
>      --title "..." --body "..."
>    ```
>
>    Use the maintainer's PR convention for the description: short,
>    essential context only, AI assistance noted briefly. Do not
>    open the PR yourself.

### B.4 — Manual review and merge

After Claude Code reports back:

1. Exit the sandbox: `./scripts/sandbox-exit.sh` (run in the
   primary checkout, not the sandbox clone). The script preserves
   the sandbox dir so you can fetch from it.
2. From the primary checkout, fetch the branch from the sandbox:
   ```sh
   cd ~/devel/claude/desktop/babble-ruby
   git fetch /tmp/babble-ruby-sandbox b1-ruby-toolchain:b1-ruby-toolchain
   # Adjust path to whatever sandbox-enter.sh used
   ```
3. Review the local branch state:
   `git log --oneline ruby-migration..b1-ruby-toolchain`,
   `git diff ruby-migration..b1-ruby-toolchain --stat`. Spot-check
   a few commits with `git show <sha>`.
4. Run the lint pipeline locally: `brew style --changed`,
   `bundle exec srb tc`, `bundle exec rspec`, `reuse lint`,
   `actionlint`, `shfmt -d bbl bin/babble script/*`,
   `shellcheck bbl bin/babble script/*`. Each should exit 0.
5. Push and open the PR using the commands from Claude Code's
   report:
   ```sh
   git push origin b1-ruby-toolchain
   gh pr create --draft --base ruby-migration \
     --title "Set up Ruby toolchain for the migration" \
     --body "..."   # use Claude Code's drafted body
   ```
6. Confirm CI passes on the PR — both the Ubuntu workflow and the
   macOS workflow.
7. The scaffolding is verbose; expect a 50+ file PR. Don't try to
   read every line — read the index, then spot-check `Gemfile`,
   `sorbet/config`, the workflow YAML, the pre-commit hook, the
   new ADR. (No `.rubocop.yml` — see B.3 Ruby tooling.)
8. If anything looks off, either iterate locally with another
   Claude Code session on the same branch, or push fixup commits
   manually. Otherwise merge with `gh pr merge --merge` (the
   default merge-commit form; not squash).

### B.5 — Stop and decide

Before starting Block C:

- [ ] Block B PR merged to `ruby-migration`
- [ ] CI green on `ruby-migration` (brew style, sorbet,
      rspec-empty, REUSE, actionlint, shellcheck)
- [ ] You've run `git pull` locally and the tools all pass
- [ ] You've read the new `docs/architecture.md` and the
      `docs/decisions/0001-…` ADR and confirm they say what you
      want them to say
- [ ] Sandbox clone cleaned up (`./scripts/sandbox-exit.sh
      --mode=destroy`)
- [ ] You're ready to commit 3–5 sessions over a few weeks to
      Block C

---

## Block C — P0 blockers in dependency order

This is the bulk of the migration work. Per the path-forward in
the PR #1 review, the order is:

1. **C.1** — P0.3 (regex fix in app_manager) + scaffolding for the
   rest of `lib/babble/`
2. **C.2** — P0.5 (brew outdated flags) + P0.6 (cancel doesn't
   abort) + P0.7 (always run brew update)
3. **C.3** — P0.4 (lsregister caching)
4. **C.4** — P0.8 (delete quarantine_purger; delegate to brew
   purge-quarantine)
5. **C.5** — P0.9 (terminal exclusion: `terminal_detector.rb`)
6. **C.6** — P0.13 (mas v7 JSON migration)
7. **C.7** — P0.10 + P0.11 + P0.12 (sorbet enforcement, RSpec
   coverage, REUSE compliance) — concurrent with prior blocks;
   final sweep

Each gets its own Claude Code session (each at Tier 3), its own PR.
Don't combine.

I won't write all seven handoff prompts now — they depend on what
landed in Block B and on early-Block-C learning. **I'll write the
prompt for C.1 only, since that one's prerequisites are stable.**
When you're ready for C.2 onward, ask me and I'll generate the
next prompt informed by what actually shipped.

### C.1 — Claude Code handoff prompt

Same Tier 3 entry pattern as Block B:

```sh
cd ~/devel/claude/desktop/babble-ruby
./scripts/sandbox-enter.sh --mode=no-remote
# Then launch Claude Code from inside the sandbox clone.
```

Copy-paste the following into Claude Code:

> I am implementing the first batch of the Ruby migration for
> babble. Block B's Ruby toolchain is in place (Gemfile, Sorbet,
> RSpec, brew-style-based lint, REUSE, CI). I am running this
> session at Tier 3 (fresh-clone-no-remote). This session lands
> the foundational `lib/babble/` module skeleton plus P0.3 (the
> bundle-ID regex fix) with proper tests.
>
> Read first:
>
> 1. `AGENTS.md` and `docs/agent-principles.md` (already loaded by
>    session start; re-read with intent — pre-action discipline
>    matters here)
> 2. `docs/technical-debt.md` (P0.3 in particular)
> 3. `docs/reviews/pr1-review.md` (B1 — the regex bug)
> 4. The PR #1 source via `gh pr diff 1` or
>    `git fetch origin copilot/rewrite-babble-as-ruby-app`. Note:
>    do NOT copy code wholesale; the entire reason we're rewriting
>    is that those files have bugs. Use as architectural reference
>    only.
> 5. `~/devel/claude/desktop/babble/archive/babble/ruby/refactor/ruby/lib/utils/running_gui_bundle_ids.rb`
>    — the prototype's working `bundleID` parser
>
> **Scope of this session:**
>
> Cut a feature branch off `ruby-migration` named
> `c1-app-manager-skeleton`. Land:
>
> 1. `lib/babble.rb` — top-level module declaration only.
> 2. `lib/babble/version.rb` — `Babble::VERSION = "0.6.0.pre"`.
> 3. `lib/babble/log.rb` — placeholder logger module per P2.1
>    (`Babble::Log.info`, `.warn`, `.debug` going to `$stderr`);
>    we'll flesh out level filtering in a later block.
> 4. `lib/babble/sh.rb` — placeholder subprocess wrapper per
>    P2.2; just enough to support C.1's tests.
>    `Babble::Sh.capture(*cmd)` returns a struct of
>    `{stdout, stderr, status}`.
> 5. `lib/babble/app_manager.rb` — first real module. Public API:
>    `running_bundle_ids` (per P0.3, with the corrected regex).
>    Other methods (`quit_app`, `quit_with_confirmation`,
>    `reopen_app`) defined as `T.unsafe(self).method(:foo)` stubs
>    that raise `NotImplementedError` — they'll be filled in by
>    later C-blocks.
> 6. `spec/spec_helper.rb` — minimal RSpec config.
> 7. `spec/babble/app_manager_spec.rb` — unit tests for
>    `running_bundle_ids`:
>    - Stubs `Babble::Sh.capture("/usr/bin/lsappinfo", "list")`
>      with a fixture
>    - Asserts the parser returns ≥ 1 bundle ID
>    - Asserts lines without `bundleID="..."` are excluded
>    - Asserts duplicates are de-duped
>    - Asserts non-zero exit status produces an empty array and a
>      log line
> 8. `spec/fixtures/lsappinfo_list_sample.txt` — captured from the
>    user's machine. Have the user generate it themselves with
>    `/usr/bin/lsappinfo list > spec/fixtures/lsappinfo_list_sample.txt`
>    and commit; do not generate or fabricate this fixture
>    yourself.
>
> **Sorbet sigs**: every public method gets a `sig`.
> `T::Sig::WithoutRuntime` is fine for performance-sensitive paths
> (none in this batch). Reference the `sig`/`T.let`/`T.unsafe`
> patterns in `~/devel/claude/desktop/homebrew-cask-tools/cmd/purge-quarantine.rb`.
>
> **Conventions** (per `docs/agent-principles.md`):
> - Module namespace `Babble::*`
> - Class with `class << self` for module-level methods
> - Minimal public API; private methods underscored where helpful
> - Open3 wrapped through `Babble::Sh`
> - `# typed: strict` and `# frozen_string_literal: true` headers
> - SPDX headers via `scripts/annotate.sh`
> - en_US spelling (org-wide rule)
>
> **Don't do in this session:**
> - Don't touch `bin/babble` (Block C.2 or later)
> - Don't port `brew_upgrade.rb`, `mas_upgrade.rb`, or
>   `bundle_launcher.rb` (later C blocks)
> - Don't delete `bbl` yet (we keep the ksh as-is until the Ruby
>   is fully working; it's the rollback path)
> - Don't write a CHANGELOG entry (we'll do this once at v0.6.0
>   release time)
>
> **PR conventions** (org-wide rules):
> - Branch: `c1-app-manager-skeleton`
> - First commit line ≤ 50 chars
> - All commits signed off (`git commit --signoff`)
> - en_US spelling
> - Run `brew style --changed`, `bundle exec srb tc`,
>   `bundle exec rspec`, `reuse lint`, and `scripts/annotate.sh`
>   locally before declaring complete
>
> **End-of-session protocol** (Tier 3):
>
> The sandbox has no remote. When the work is done:
>
> 1. Confirm all lint and test commands pass locally.
> 2. Output a final report: branch name, commit subjects, what
>    landed, known issues if any, and the exact fetch + push +
>    `gh pr create` procedure for the user to run from the primary
>    checkout (same shape as Block B's report).
> 3. Do not open the PR yourself.

After C.1 lands, ask me to generate the C.2 prompt. The
conditional state means I want to see what actually shipped before
specifying the next block.

---

## Reference: directories that get created and where

| Path | Block | What it holds |
|------|-------|---------------|
| `archive/_OPENING_PROMPT.txt` | done (this session) | session artifact, gitignored |
| `docs/`, `docs/reviews/`, `docs/decisions/` | done (this session) | this doc, technical-debt, reviews |
| `.gitignore` | done (this session) | excludes prompt artifact and Ruby/macOS noise |
| `AGENTS.md`, `CLAUDE.md`, `CLAUDE.md.license` | 0 | agent context |
| `docs/agent-principles.md` | 0 | universal operating principles |
| `.claude/settings.json` | 0 | babble-specific perms |
| `scripts/sandbox-*.sh` | 0 | Tier 3/4 isolation scripts |
| `Gemfile`, `Gemfile.lock`, `.rspec`, `.bundle/config` | B | Ruby toolchain (no `.rubocop.yml`) |
| `sorbet/config`, `sorbet/rbi/` | B | Sorbet config |
| `LICENSES/`, `scripts/annotate.sh` | B | REUSE setup |
| `.githooks/pre-commit` | B | pre-commit hook |
| `.github/workflows/{ci,lint}.yml` | B | CI |
| `bin/setup` | B | dev-deps install |
| `CONTRIBUTING.md` | B | human contributor guide (repo-specific only) |
| `docs/architecture.md`, `docs/decisions/0001-…` | B | architecture + first ADR |
| `lib/babble/`, `spec/`, `spec/fixtures/`, `spec/manual/` | C.1 | code |
| `bin/babble` | C.2 | bash wrapper |
| `swift/src/`, `swift/build/` | C (later) | Swift quit alert + cache |
| `config/apps.example.yml` | C (P1.4) | example user config |
| `.claude/skills/{dev-cycle,release-check,review-pr,test}/` | After Block C | skill files |

You don't need to pre-create most of these. Each block creates
what it needs. The only manual `mkdir`s are in Block 0
(`mkdir -p .claude scripts`).

---

## Tech-debt items on the scaffolding repo (not babble)

These came up during this session but belong on
`~/devel/claude/desktop/scaffolding/`, not babble. Note them in
case the user wants to file issues on that repo (and see also
P2.10, P2.11 in babble's technical-debt for the babble-side
tracking):

- **scaffolding/project/ subdirectory not yet populated.** The
  README documents `project/AGENTS.md`, `project/CLAUDE.md`,
  `project/settings.json`, `project/docs/agent-principles.md`,
  `project/githooks/pre-commit`, `project/workflows/*.yml`,
  `project/ISSUE_TEMPLATE/`. None of these exist on disk. The
  files live at `_claude-config-baseline/project/` for now.
- **scaffolding/scripts/ missing most utility scripts.** The
  README documents `annotate.sh`, `rewrite-pr-as-merge-commit.sh`,
  `sandbox-enter.sh`, `sandbox-exit.sh`, `sandbox-vm-enter.sh`,
  `sandbox-vm-exit.sh`, `sandbox-vm-bootstrap.sh`. Only
  `sync-principles.sh` exists. The others live at
  `blackoutd/scripts/`.
- **scaffolding/ has no branch-protection guidance.** Bootstrap
  docs should include a recipe for setting up branch protection
  rulesets (see babble's tech-debt P2.10).
- **scaffolding/ has no global/ subdirectory.** The README
  documents `global/CLAUDE.md`, `global/AGENTS.md`,
  `global/settings.json`. Files live at
  `_claude-config-baseline/global/`.
- **`_claude-config-baseline/` should be decommissioned** once
  scaffolding is the canonical home (P2.11).

These are not blockers for babble's migration — the workaround
(use the `_claude-config-baseline/` paths in Block 0) is captured
in the instructions above. If the scaffolding consolidation
session happens *before* Block 0, update the source paths in 0.1
to use `scaffolding/` instead.

---

## Tech-debt items on the dot-github repo (not babble)

Also surfaced this session, also out of scope for babble:

- **dot-github has no `profile/CONTRIBUTING.md`.** Org-wide
  conventions (en_US spelling, 50-char commit subjects, signed
  commits, modern git verbs) belong there so individual repos
  don't duplicate them. babble's `CONTRIBUTING.md` (per P2.9)
  references it.

---

## When something doesn't fit this plan

This document is the plan as understood at the end of the planning
session. As Block 0 / B / C unfold, things will change:

- A bug in PR #1 we missed will surface during the cherry-pick
- Homebrew will release something that obsoletes part of the design
- A C-block's prerequisite will turn out to be wrong
- Personal time constraints will demand re-prioritization

When that happens: **update [`technical-debt.md`](technical-debt.md)
before you update the code.** The register is the source of truth;
this handoff document is downstream of it. If a P0 needs to become
a P1 or vice versa, update the register, then update this handoff,
then code.

This applies double to Claude Code sessions. If a session reveals
that the assumptions in its handoff prompt are wrong, the right
move is to stop, surface the issue in the chat, update the planning
docs, and restart the session with a corrected prompt — not to
plow through and hope for the best.

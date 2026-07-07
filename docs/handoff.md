<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Handoff — what comes next

> **For preservation of pre-pivot work**, see
> [`migration-investigation/`](migration-investigation/) — the year+ of
> `refactor/modular` work and rationale for the external-command
> pivot.

This is the action document for the babble migration. It was first
written for the standalone-Ruby-app shape and **regenerated after the
external-command pivot** (W3 in the master plan): babble ships as a
Homebrew external command (`brew babble`) in a tap, modeled on
`homebrew-cask-tools`. Blocks B and C below target that shape. The
decisions this regeneration encodes live in
[`migration-investigation/01-decisions.md`](migration-investigation/01-decisions.md)
(entry-point shape, class-vs-module classification, ⨀ output
formatting, tap distribution) — do not re-litigate them here.

It is sequenced so each block can be done in isolation, with clear
stop-and-decide gates between blocks.

The blocks are:

1. **Block A — Sanity, ship v0.5.2, branch hygiene.** Manual; no
   Claude Code. **Done** (see status notes inline).
2. **Block 0 — Scaffold the Claude Code config in this repo.**
   Manual; no Claude Code (this is the prerequisite for *any* Claude
   Code session). ~30–45 min.
3. **Block B — Tap structure and toolchain on `ruby-migration`.**
   Claude Code handoff prompt at the end of this block. **Run at
   Tier 3.** ~1 session.
4. **Block C — P0 blockers in dependency order.** Claude Code handoff
   prompt for each blocker; sequence matters. **Tier 3 throughout.**
   ~3–5 sessions.

Block C only starts after Block B's PR is merged and you've done a
manual smoke pass. Don't try to fold C into B — the tap toolchain is
its own deliverable and reviewing both at once will be exhausting.

## What the external-command shape changes

Compared to the pre-pivot plan (see git history of this file):

- **No Gemfile, no `.bundle/`, no project Sorbet config, no
  project rubocop.** Babble runs inside Homebrew's Ruby process with
  Homebrew's vendored gems. The entire Ruby toolchain is `brew style`,
  `brew typecheck`, and `brew tests` — same as cask-tools.
- **No `bin/babble` Bash wrapper.** The entry point *is* `brew
  babble`; Homebrew handles Ruby bootstrap. The portable-Ruby
  gymnastics (P1.1) disappear.
- **Entry point** is `Homebrew::Cmd::Babble < AbstractCommand` in
  `cmd/babble.rb`; supporting classes live under `cmd/babble/` in the
  `Babble::*` namespace (brew's tap command discovery only scans
  `cmd/*.rb`, so `cmd/babble/*.rb` files do not become phantom
  commands).
- **Distribution** becomes `brew tap toobuntu/babble`, which makes
  `brew babble` available. The GitHub repo gets renamed
  `toobuntu/babble → toobuntu/homebrew-babble` per Homebrew's
  tap-naming convention. **Rename accelerated** (2026-07-06, was the
  v0.6.0 gate): `Homebrew/actions/setup-homebrew` auto-checks-out
  only `homebrew-*` repos, so renaming now gives babble's CI the
  same checkout behavior cask-tools relies on and avoids a
  temporary explicit-checkout workaround; nobody taps babble yet,
  and GitHub redirects the old name. `brew babble` stays a stub
  until v0.6.0.
- **Output formatting**: Homebrew's `oh1`/`ohai`/`opoo`/`ofail`
  helpers with the message text prefixed by `⨀`, producing
  `==> ⨀ Babble message` — visually distinct from Homebrew's own
  `==> …` lines. Locked decision (option 2); gets an ADR in Block B.
- **Bundle discovery**: the launcher C-block consumes
  `Homebrew::CaskTools::BundleDiscovery` from the cask-tools tap
  (extracted there by W7) instead of porting refactor/modular's
  three-tier resolver. Note the namespace: `Homebrew::CaskTools`, not
  `Homebrew::Cask` — defining `Homebrew::Cask` would shadow the
  top-level `::Cask` module for brew internals and break them at
  runtime.

## Lint, typecheck, and test strategy

Babble uses Homebrew's own pipeline, exactly like cask-tools:

- **`brew style <files>`** (or `--changed`) for lint. Homebrew's
  rubocop config; no project-local `.rubocop.yml`. Shell files get
  Homebrew's shfmt/shellcheck config verbatim through the same
  command — never RF's shell-lint (the sync manifest excludes
  babble from RF's `shell_lint` set). `.shellcheckrc` and
  `.editorconfig` are verbatim copies of Homebrew/brew's own
  (adopted 2026-07-03, replacing the stale pre-pivot rules), with
  upstream-tracking via repo-foundation's `upstreams:` list
  proposed. RF-lineage POSIX scripts carry a one-line shellcheck
  exemption for Homebrew's optional checks.
- **`brew typecheck`** for Sorbet, run against the brew repo with the
  tap files hardlinked in (see `scripts/run-tests.sh` pattern below).
  Every non-spec file is `# typed: strict` with `sig`s throughout;
  spec files are never `typed: strict`.
- **`brew tests --only=…`** for RSpec. brew only discovers specs
  inside `$(brew --repo)/Library/Homebrew/test/`, so babble adapts
  cask-tools' `scripts/run-tests.sh`: hardlink `cmd/babble.rb`, the
  `cmd/babble/` tree, and `test/` specs into the brew repo, run, then
  unlink. CI does the same inline (see cask-tools'
  `.github/workflows/ci.yml`).

## Preconditions

### Machine-level Claude Code config

Before any Claude Code session on any project, the maintainer's
machine needs `~/.claude/CLAUDE.md` and `~/.claude/settings.json`.

The canonical source is now
`~/devel/claude/desktop/toobuntu/repo-foundation/provides/claude-user/`
(W1 Sessions 1–4 content; on disk, commit pending W1 Session 5). The
older `_claude-config-baseline/` tree is deprecated — if
repo-foundation's copy is missing on a fresh machine, fall back to
`~/devel/claude/desktop/_claude-config-baseline.deprecated/global/`.

### Tier guidance (per blackoutd ADR 0007)

Each Claude Code session in this plan runs at one of the four
isolation tiers defined in
`~/devel/claude/desktop/toobuntu/blackoutd/docs/decisions/0007-layered-isolation-strategy.md`.
Read the ADR if you haven't recently. Short summary:

- **Tier 1** — Primary checkout, in-host Seatbelt + permission rules.
- **Tier 2** — In-tree worktree. Workflow isolation only.
- **Tier 3** — Fresh-clone-no-remote sandbox via
  `scripts/sandbox-enter.sh --mode=no-remote`. **For sessions that
  fire `excludedCommands` more than ~3 times** or any multi-commit
  autonomous work.
- **Tier 4** — Lume macOS VM. Not needed for babble.

W6 in the master plan renames these scripts to
`isolate enter --level=detached` etc.; until W6 ships, the
`sandbox-enter.sh` names below are current.

Per-block tier recommendations:

| Block | Tier | Rationale |
|-------|------|-----------|
| Block A | n/a | Manual; done |
| Block 0 | n/a | Manual; no Claude Code session |
| Block B | **3** | Multi-commit, broad file changes |
| Block C.1–C.7 | **3** | Multi-commit; every block ends in a PR |

The `sandbox-enter.sh` script now lives in
`~/devel/claude/desktop/toobuntu/repo-foundation/scripts/sandbox-enter.sh`
(repo-foundation took over from blackoutd as the canonical home;
blackoutd's copies are gone). Copy it (plus `sandbox-exit.sh`) into
`scripts/` during Block 0 so it's in place when Block B starts.

---

## Block A — Sanity, ship v0.5.2, branch hygiene

**Status: done.** Kept for the record; per-item status:

- **A.1 planning artifacts** — landed on `main` (PR #4
  `preservation-archive`, PR #5 `w3-doc-refinements`, PR #6
  `reorg-reference-fixup`).
- **A.2 rename `tech-debt.md` → `technical-debt.md`** — done in the
  W3 doc-regeneration branch (this branch), together with this file's
  regeneration.
- **A.3 commit planning artifacts** — done (see A.1).
- **A.4 v0.5.2** — tagged from `f2f8f12` and released; final ksh
  release.
- **A.5 PRs #1 and #3** — closed with disposition comments;
  `docs/reviews/` has the analyses.
- **A.6 worktrees / separate clone** — **superseded by the pivot.**
  The plan to create a separate `babble-ruby` clone with a pushed
  `ruby-migration` branch was written for the standalone-app shape
  and was not executed. Under the external-command shape, migration
  work happens in *this* repo (which later becomes the tap). The
  `babble-refactor-modular` worktree is intentionally retained as the
  daily-driver runtime until W3 ships (see master plan W2 cleanup
  notes). Block 0 creates the `ruby-migration` branch here.
- **A.7 branch protection** — configure when Block 0 pushes the
  `ruby-migration` branch (rules as in the pre-pivot text: PR-only
  `main`, required checks `style`/`brew_tests` once Block B's CI
  exists, signed commits, no force pushes).

---

## Block 0 — Scaffold the Claude Code config on `ruby-migration`

Manual, no Claude Code. Purpose: land the project-level agent
scaffolding (`AGENTS.md`, `CLAUDE.md`, `docs/agent-principles.md`,
`.claude/settings.json`, sandbox tier scripts) so every subsequent
Claude Code session starts with guard rails in effect.

> **RF-sync coordination.** repo-foundation is pushed but **not yet
> synced** to babble; the first sync (plus its cleanup pass) happens
> after Block B merges, as its own step. These baseline copies are
> therefore **interim guardrails**, sourced read-only from
> `~/devel/claude/desktop/toobuntu/repo-foundation/` (`provides/` for
> the repo files, `scripts/` for the sandbox scripts); the first sync
> reconciles them. Do not hand-add the other RF-managed repo-health
> files (`.githooks/pre-commit`, `lint.yml`, `.editorconfig`, RF
> shell-lint configs, commit-convention / org-ADR-policy plumbing) —
> they arrive via the sync. See the master plan § W3 "RF-sync
> coordination".

### 0.1 — Create the branch and copy the templates

Working in this repo:

```sh
cd ~/devel/claude/desktop/toobuntu/babble
git switch main && git pull
git switch -c ruby-migration
git push -u origin ruby-migration

# Source: repo-foundation (W1 Sessions 1-4, on disk) — provides/
# for the repo files, scripts/ for the sandbox scripts (RF took
# over from blackoutd as the canonical home).
RF=~/devel/claude/desktop/toobuntu/repo-foundation

mkdir -p .claude
cp "$RF/provides/repo/AGENTS.baseline.md"     AGENTS.md
cp "$RF/provides/repo/CLAUDE.md"              CLAUDE.md
cp "$RF/provides/repo/settings.baseline.json" .claude/settings.json
cp "$RF/docs/agent-principles.md"             docs/agent-principles.md

cp "$RF/scripts/sandbox-enter.sh"             scripts/sandbox-enter.sh
cp "$RF/scripts/sandbox-exit.sh"              scripts/sandbox-exit.sh
chmod +x scripts/sandbox-*.sh
```

Add `.license` sidecars where a file format can't carry an SPDX
header (`.claude/settings.json.license`, `CLAUDE.md.license` if
CLAUDE.md is the thin `@AGENTS.md` pointer) — run
`scripts/annotate.sh` (already in this repo since W2) rather than
hand-writing them.

### 0.2 — Adapt `AGENTS.md` for babble

Fill the baseline's placeholders. Suggested content:

Project summary:

```
Babble is an interactive upgrade routine for Homebrew (formulae and
casks), Mac App Store apps via mas, and macOS system updates via
softwareupdate. Currently shipping as a ksh script (bbl, v0.5.2); in
active migration to a Homebrew external command (`brew babble`) in
this repo, which becomes the toobuntu/babble tap (repo renamed to
homebrew-babble at v0.6.0). Modeled on homebrew-cask-tools. Target
platform: macOS 14+ on Apple Silicon and Intel.
```

Key constraints:

```
- Target: macOS 14+ (Sonoma); macOS 15+ for the Swift quit_alert
  binary (Swift 5.9 syntax requires Xcode 15)
- Runtime: Homebrew's Ruby, inside the brew process (external
  command). No Gemfile; Homebrew's vendored gems only.
- Dependencies: brew (required), mas (optional), toobuntu/cask-tools
  tap (for `brew purge-quarantine` delegation and
  Homebrew::CaskTools::BundleDiscovery), Xcode CLT (required for the
  Swift quit_alert auto-compile)
- Codesigning: ad-hoc only (no Apple Developer cert)
- License: GPL-3.0-or-later (single license)
- Lint: `brew style` (Homebrew rubocop config; no project rubocop)
- Typecheck: `brew typecheck` with tap files hardlinked into
  $(brew --repo) (scripts/run-tests.sh pattern)
- Tests: `brew tests --only=…` via scripts/run-tests.sh
- Output: Homebrew helpers with ⨀-prefixed messages (ADR 0002)
```

Project-specific tools (danger list):

```
- bbl (the ksh script) — DO NOT run. It performs real upgrades.
- brew babble (once it exists) — same restriction.
- osascript / JXA app-quit — quits running user apps; always ask.
- xcrun swiftc — auto-compiles swift/src/quit_alert.swift on first
  run; output stays inside the project tree.
- scripts/run-tests.sh — hardlinks files into $(brew --repo); do not
  run brew update/upgrade/update-reset concurrently.
```

"Documents to read on first load": `docs/agent-principles.md`,
`docs/technical-debt.md`, `docs/handoff.md`, `docs/decisions/`
(once Block B lands them), `docs/reviews/` for PR work, and
`docs/migration-investigation/01-decisions.md` for the locked design
decisions.

### 0.3 — Adapt `.claude/settings.json` for babble

Replace the baseline placeholders with babble's rules. This layers on
top of `~/.claude/settings.json`:

```jsonc
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",

  "permissions": {
    "allow": [
      "Bash(brew style)",
      "Bash(brew style:*)",
      "Bash(brew typecheck)",
      "Bash(brew tap-info:*)",
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
      "Bash(shellcheck:*)",
      "Bash(shfmt -d:*)",
      "Bash(actionlint:*)",
      "Bash(reuse lint)",
      "Bash(reuse --no-multiprocessing lint)",
      "Bash(xcrun --find swiftc)",
      "Bash(script/log-since-latest-tag)",
      "Bash(script/release-notes)"
    ],

    "ask": [
      "Bash(./bbl)",
      "Bash(bbl)",
      "Bash(brew babble:*)",
      "Bash(brew tests:*)",
      "Bash(scripts/run-tests.sh:*)",
      "Bash(brew ruby:*)",
      "Bash(brew tap:*)",
      "Bash(brew untap:*)",
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
      "scripts/run-tests.sh:*",
      "brew tests:*",
      "brew typecheck:*"
    ]
  },

  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "if [ \"$(git -C \"${CLAUDE_PROJECT_DIR:-.}\" branch --show-current)\" = \"main\" ]; then echo 'Direct edits to main are not allowed. Create a feature branch first, e.g. git switch -c b1-tap-toolchain.' >&2; exit 2; fi",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

Notes:

- `brew style` / `brew typecheck` are read-only diagnostics; allowed.
- `brew tests`, `scripts/run-tests.sh`, and `brew typecheck` need
  `excludedCommands` entries because the hardlink harness writes into
  `$(brew --repo)` — outside the project write root. Each entry is a
  partial sandbox bypass primitive; this is part of why every B/C
  session runs at Tier 3.
- `brew ruby` executes arbitrary Ruby inside brew — `ask`, not allow.
- The `:*` suffix convention per blackoutd ADR 0005/0007 (bare and
  space-asterisk forms are buggy).

### 0.4 — `docs/agent-principles.md` (probably no edits)

Same rule as before: overrides go in `AGENTS.md`; the principles file
only changes if the change applies to every repo — in which case
update the canonical in repo-foundation first, then re-copy.

### 0.5 — Verify and commit

```sh
jq empty .claude/settings.json && echo OK
ls -la AGENTS.md CLAUDE.md docs/agent-principles.md scripts/sandbox-*.sh
reuse lint          # annotate.sh new-file sidecars in place?

git add AGENTS.md CLAUDE.md* .claude/ docs/agent-principles.md scripts/
git commit --signoff -m "Add Claude Code project scaffolding"
git push origin ruby-migration
```

Subject is 38 chars. Configure the A.7 branch-protection rulesets
now that `ruby-migration` exists on origin.

### 0.6 — Stop and decide

- [ ] `AGENTS.md` reads correctly end-to-end for the external-command
      shape (no stale Gemfile/bin-babble references)
- [ ] `.claude/settings.json` parses (`jq empty`)
- [ ] Sandbox scripts present and executable
- [ ] `git push` succeeded; branch protection configured
- [ ] Ready to commit ~1 session to Block B

---

## Block B — Tap structure and toolchain on `ruby-migration`

Block 0 landed the agent scaffolding. This block turns the repo into
a working Homebrew tap with a stub command, CI, and docs — the
external-command replacement for the old "Ruby toolchain" block.
The result: `brew babble --help` works (stub), `brew style`,
`brew typecheck`, `brew tests`, `reuse lint`, and `actionlint` all
pass locally — but no upgrade logic is ported yet.

This discharges the toolchain part of **P0.2** in
[`technical-debt.md`](technical-debt.md) as revised for the
external-command shape.

> **RF-sync coordination (scopes this block).** repo-foundation is
> pushed but not yet synced to babble; babble keeps its pre-sync
> infra during W3. Block B lands only the **Homebrew-aligned**
> pieces: `ci.yml` (style + brew_tests jobs), `scripts/run-tests.sh`,
> the `cmd/babble.rb` stub plus `cmd/babble/{version,formatter}.rb`,
> and ADRs 0001–0003 (babble-specific, MADR 4.0 via `adrs`, numbered
> from babble's own 0001; org-wide ADRs live in repo-foundation).
> **Amended 2026-07-03 (in-session maintainer decision):** the
> RF-managed repo-health files are **hand-staged ahead of the first
> sync** so babble is fully set up now — copies of RF's canonicals
> per the sync manifest's babble entry, each carrying a
> hand-copy/do-not-modify header the first real sync reconciles:
> the `.githooks/` chain (dispatcher, pre-push, 15-prose / 30-brew /
> 50-adrs plugins, plus babble's own 60-babble-typecheck),
> `lint.yml`, `actionlint.yml`, `.github/zizmor.yml` +
> `actionlint.yaml` + matcher, `.pinact.yaml`, the shared scripts
> (lint-perms, lint-unicode, re-sign-unpushed, rewrite-pr, fixed
> annotate.sh), and sync-readiness sentinels in `AGENTS.md` /
> `.gitignore` plus `.claude/settings.addenda.json`. babble still
> defers to `brew style` verbatim for shell — it is excluded from
> RF's `shell_lint` set; `.shellcheckrc`/`.editorconfig` are now
> Homebrew/brew's verbatim copies instead. See the master plan § W3
> "RF-sync coordination" and P0.2 in `technical-debt.md`.

### B.1 — Pre-flight (manual, before launching Claude Code)

Decisions already locked (from
`migration-investigation/01-decisions.md` and the master plan; do not
re-open in-session):

1. **Single license** GPL-3.0-or-later. (`LICENSES/` and
   `scripts/annotate.sh` are already in the repo from W2.)
2. **macOS floor**: 14; Swift binary needs 15 (Xcode 15).
3. **Lint/typecheck/tests**: `brew style` / `brew typecheck` /
   `brew tests` only. No Gemfile, no `.rubocop.yml`, no `sorbet/`
   dir, no `.rspec`.
4. **Entry point**: `Homebrew::Cmd::Babble < AbstractCommand` in
   `cmd/babble.rb`; future support classes under `cmd/babble/`.
5. **Output**: ⨀ prefix on `oh1`/`ohai`/`opoo`/`ofail` (ADR below).
6. **ADRs**: MADR 4.0 via `adrs` (org convention; see
   `adrs-formula/docs/notes/adr-authoring-workflow.md`). Block B runs
   `adrs init` (`adrs.toml` with `adr_dir = "docs/decisions"`).
7. **Skill files** (`.claude/skills/`): defer until after a few
   C-blocks.

Also set up the live-tap symlink for manual testing (dev clone
doubles as the installed tap, mirroring the Copilot-sandbox layout
cask-tools documents):

```sh
mkdir -p "$(brew --repository)/Library/Taps/toobuntu"
ln -sfn ~/devel/claude/desktop/toobuntu/babble \
  "$(brew --repository)/Library/Taps/toobuntu/homebrew-babble"
brew tap-info toobuntu/babble   # sanity: brew sees the tap
```

(Do this on the primary checkout, not inside a Tier 3 sandbox clone —
the sandbox clone tests via `scripts/run-tests.sh`, not via a live
tap.)

### B.2 — Enter Tier 3 sandbox before launching Claude Code

```sh
cd ~/devel/claude/desktop/toobuntu/babble
./scripts/sandbox-enter.sh --mode=no-remote
# Verify inside the sandbox clone:
git remote -v       # empty
git switch ruby-migration
ls -la .claude/     # settings.json from Block 0
```

Then launch Claude Code from inside the sandbox clone.

### B.3 — Claude Code handoff prompt for Block B

Copy-paste the following into Claude Code:

> I am converting babble into a Homebrew external command tap. Block
> 0 already landed the Claude Code project scaffolding. I am running
> this session at Tier 3 (fresh-clone-no-remote). The reference repo
> to model on is `~/devel/claude/desktop/toobuntu/homebrew-cask-tools/`
> — treat its layout, CI, and conventions as canonical unless this
> prompt says otherwise.
>
> Read these documents first, in order:
>
> 1. `AGENTS.md` and `docs/agent-principles.md` (already loaded at
>    session start; re-read with intent)
> 2. `docs/handoff.md` § Block B (your scope)
> 3. `docs/technical-debt.md` (P0.2 as revised for the
>    external-command shape)
> 4. `docs/migration-investigation/01-decisions.md` §§ "Class-vs-module
>    decomposition pattern", "Entry point shape", "Output formatting",
>    "Tap distribution" (locked decisions)
> 5. `~/devel/claude/desktop/toobuntu/homebrew-cask-tools/cmd/purge-quarantine.rb`
>    (model for `AbstractCommand`, `cmd_args`, Sorbet sigs)
> 6. `~/devel/claude/desktop/toobuntu/homebrew-cask-tools/.github/workflows/ci.yml`
>    and `scripts/run-tests.sh` (the hardlink test/CI pattern —
>    including the `lib/` hardlinking added by W7)
> 7. `~/devel/claude/desktop/toobuntu/homebrew-cask-tools/AGENTS.md`
>    §§ Code Standards, Key Guidelines (house Ruby/Sorbet style)
>
> Decisions already locked (do not re-litigate): single license
> GPL-3.0-or-later; macOS floor 14 (Swift binary 15); `brew style` /
> `brew typecheck` / `brew tests` only — NO Gemfile, NO
> `.rubocop.yml`, NO `sorbet/` directory, NO `.rspec`; entry point
> `Homebrew::Cmd::Babble` in `cmd/babble.rb`; ⨀ output prefix;
> MADR 4.0 ADRs via `adrs`.
>
> Cut a feature branch off `ruby-migration` named `b1-tap-toolchain`
> and land the following in commits that you propose for approval:
>
> **Tap command stub.**
>
> - `cmd/babble.rb` — `Homebrew::Cmd::Babble < AbstractCommand`,
>   `# typed: strict`, SPDX header via `scripts/annotate.sh`.
>   `cmd_args` with description ("An interactive upgrade routine for
>   Homebrew, Mac App Store, and macOS software") and the first two
>   switches: `--no-update` (skip the brew-update phase) and
>   `--dry-run` (print what would be upgraded without doing it).
>   `run` prints the banner via
>   `Babble::Formatter.oh1 "Babble #{Babble::VERSION}"` and a
>   "migration in progress; phases land in C-blocks" notice via
>   `Babble::Formatter.ohai`, then exits 0 — the ⨀ prefix comes
>   from the formatter, never hardcoded at call sites. Guard
>   `raise UsageError … unless OS.mac?` like purge-quarantine.
> - `cmd/babble/version.rb` — `Babble::VERSION = "0.6.0.pre"`,
>   frozen, typed strict. Required from `cmd/babble.rb` via
>   `require_relative "babble/version"`.
> - `cmd/babble/formatter.rb` — `Babble::Formatter` module
>   (`class << self` form): `oh1`, `ohai`, `opoo`, `ofail` wrappers
>   that prefix the message with `⨀ ` and delegate to Homebrew's
>   helpers (include `Utils::Output::Mixin`). This is the single
>   place the ⨀ convention lives. Unit-test it.
>
> **Test harness.**
>
> - `test/cmd/babble_spec.rb` — spec for the stub: args parse,
>   `--dry-run` accepted, run prints the ⨀ banner (capture stdout).
> - `test/cmd/babble/formatter_spec.rb` — Formatter unit specs.
> - `scripts/run-tests.sh` — adapt cask-tools' version (including
>   W7's `lib/`-style handling for the `cmd/babble/` subtree: brew
>   only auto-discovers `cmd/*.rb`, and hardlinked files resolve
>   `require_relative` against the hardlink location, so the
>   `cmd/babble/` tree must be hardlinked too).
>
> **CI.** Replace `.github/workflows/tests.yml` with:
>
> - `ci.yml` — modeled on cask-tools': `style` job
>   (`brew style --changed` on macos-latest with the gems + style
>   caches) and `brew_tests` job (hardlink `cmd/babble.rb`,
>   `cmd/babble/*.rb`, and `test/` specs into `$(brew --repo)`, run
>   `brew tests --only=cmd/babble` plus one `--only` per spec file,
>   unlink in an `always()` step). Add a `typecheck` step to the
>   style job running `brew typecheck` with the same hardlinks —
>   verify it picks up the tap files; if it does not, document that
>   typecheck is local-only for now and move on (do not sink the
>   session into it).
> - `lint.yml` + `actionlint.yml` — hand-staged copies of RF's
>   canonicals (2026-07-03 amendment): reuse / lint-unicode /
>   lint-perms / lint-adrs, and actionlint + zizmor with the
>   Homebrew/actions ref-pin policy. Shell lint stays with `brew
>   style` in ci.yml (babble is excluded from RF's shell_lint set).
> - Update `.github/dependabot.yml` for github-actions (no bundler —
>   there is no Gemfile).
>
> **ADRs (MADR 4.0, via `adrs init` + `adrs new`).**
>
> - `adrs.toml` (`[templates] format = "madr"`,
>   `adr_dir = "docs/decisions"`).
> - `docs/decisions/0001-homebrew-external-command-shape.md` — the
>   pivot decision: context (year+ refactor/modular, PR #1/#3
>   failures, cask-tools precedent), decision (external command in a
>   tap; repo renamed homebrew-babble at v0.6.0), consequences (brew
>   toolchain; no Gemfile; brew process constraints), links to
>   `migration-investigation/`.
> - `docs/decisions/0002-output-formatting-babble-prefix.md` — the ⨀
>   decision (option 2): symbol-not-color, severity colors inherited
>   from opoo/ofail, HOMEBREW_NO_COLOR respected. Source:
>   `migration-investigation/01-decisions.md` § Output formatting.
> - `docs/decisions/0003-swift-quit-alert-build-strategy.md` —
>   adapt `migration-investigation/adrs/0001-…` (auto-compile via
>   xcrun swiftc, SHA256 sidecar, osascript fallback) to MADR 4.0;
>   mark the investigation copy as superseded-by-this.
>
> **Docs.**
>
> - `docs/architecture.md` — initial draft: entry flow (`brew babble`
>   → AbstractCommand → phase classes), module structure table (the
>   planned `Babble::*` classes from 01-decisions § W3 component
>   classification, marked "lands in C.x"), lint/typecheck/test
>   pipeline (the hardlink pattern), tap layout, ⨀ output convention,
>   BundleDiscovery consumption plan (cask-tools tap dependency).
> - `README.md` — note the migration is in progress; point at v0.5.2
>   for the released ksh version; add the `brew tap toobuntu/babble`
>   install shape as "coming at v0.6.0"; link docs/.
>
> **What NOT to do in this session:**
>
> - Don't touch `bbl` (it stays the working daily driver / rollback
>   path until v0.6.0)
> - Don't port any phase logic (`brew update`/`upgrade`, mas, macOS,
>   app quit/reopen) — that's Block C
> - Don't create Gemfile, `.rubocop.yml`, `sorbet/`, `.rspec`, or
>   `bin/babble` — wrong shape (see § What the external-command
>   shape changes)
> - Don't touch `swift/`, `config/`, or `stash/`
> - Don't rename the GitHub repo (that's the v0.6.0 gate)
> - Don't edit `AGENTS.md` / `.claude/settings.json` (Block 0 landed
>   them; propose changes in the report instead)
> - Don't fork the hand-staged RF canonicals (files whose header
>   says "do not modify it directly") — upstream fixes to
>   repo-foundation instead
> - Don't apply RF's shell-lint to babble's own shell — `brew style`
>   owns it; `.shellcheckrc`/`.editorconfig` track Homebrew/brew
>   verbatim
>
> **Conventions** (org-wide): first commit line ≤ 50 chars; commits
> signed off (`git commit --signoff`); en_US spelling; long options
> in scripts; SPDX headers only via `scripts/annotate.sh`.
>
> **End-of-session protocol (Tier 3).** The clone has no remote;
> `git push` will fail and `gh` is unavailable. When done:
>
> 1. Confirm `brew style --changed`, `scripts/run-tests.sh`,
>    `reuse lint`, `actionlint`, `shellcheck`/`shfmt -d` all pass
>    locally (note any that could not run in the sandbox and why).
> 2. Output a final report: branch name, commit subjects, what
>    landed / was deferred with rationale, and the exact procedure
>    for the user to fetch from this sandbox clone, push, and open
>    a draft PR against `ruby-migration` from the primary checkout:
>
>    ```sh
>    cd ~/devel/claude/desktop/toobuntu/babble
>    git fetch <sandbox-path> b1-tap-toolchain:b1-tap-toolchain
>    git push origin b1-tap-toolchain
>    gh pr create --draft --base ruby-migration --title "…" --body "…"
>    ```
>
> 3. Do not push or open the PR yourself.

### B.4 — Manual review and merge

1. Exit the sandbox (`./scripts/sandbox-exit.sh`; it preserves the
   sandbox dir for the fetch).
2. Fetch the branch into the primary checkout; review
   `git log --oneline ruby-migration..b1-tap-toolchain` and
   `git diff ruby-migration..b1-tap-toolchain --stat`; spot-check
   `cmd/babble.rb`, the workflows, `scripts/run-tests.sh`, the ADRs.
3. Re-sign the fetched commits before pushing (the sandbox commits
   are unsigned): use
   `repo-foundation/scripts/re-sign-unpushed.sh` or the inline
   `git rebase --exec 'git commit --amend --no-edit --gpg-sign'`
   recipe from `~/.claude/CLAUDE.md`.
4. Run the pipeline yourself: `brew style --changed`,
   `scripts/run-tests.sh`, `reuse lint`, `actionlint`. With the
   live-tap symlink from B.1: `brew babble --help` and `brew babble`
   (stub banner).
5. Push, open the draft PR, confirm CI green, merge with
   `gh pr merge --merge`.

### B.5 — Stop and decide

- [ ] Block B PR merged to `ruby-migration`; CI green
- [ ] `brew babble` prints the ⨀ stub banner on this machine
- [ ] You've read the three new ADRs and `docs/architecture.md` and
      they say what you want them to say
- [ ] Sandbox clone cleaned up
      (`./scripts/sandbox-exit.sh --mode=destroy`)
- [ ] Ready for 3–5 Block C sessions

---

## Block C — P0 blockers in dependency order

Order (P0 numbering per [`technical-debt.md`](technical-debt.md), as
revised for the external-command shape):

1. **C.1** — P0.3 (lsappinfo `bundleID` parsing) + the `Babble::*`
   class skeleton under `cmd/babble/`
2. **C.2** — P0.5 (brew outdated flags) + P0.6 (cancel aborts) +
   P0.7 (always run brew update) — the BrewUpdate/BrewUpgrade phases
3. **C.3** — bundle launcher consuming
   `Homebrew::CaskTools::BundleDiscovery` (P0.4's caching concern is
   discharged by BundleDiscovery's shared lsregister cache plus the
   cheap `osascript` polling predicate). **Soft prerequisite: W7
   merged in cask-tools** — if W7 hasn't merged when C.3 comes up,
   ship refactor/modular's 3-tier launcher and swap in a follow-up.
4. **C.4** — P0.8 (no quarantine purger; delegate to
   `brew purge-quarantine`, requiring the cask-tools tap)
5. **C.5** — P0.9 (terminal exclusion: `Babble::TerminalDetector`)
6. **C.6** — P0.13 (mas v7 `--json` migration)
7. **C.7** — P0.10 + P0.11 + P0.12 (typecheck/tests/REUSE
   enforcement sweep)

Each gets its own Tier 3 Claude Code session and its own PR into
`ruby-migration`. Don't combine.

I'll write the prompt for C.1 only; prompts for C.2+ get generated
after C.1 ships, informed by what actually landed.

### C.1 — Claude Code handoff prompt

Same Tier 3 entry pattern as Block B. Copy-paste into Claude Code:

> I am implementing the first logic batch of babble's external-command
> migration. Block B's tap toolchain is in place (`cmd/babble.rb`
> stub, `cmd/babble/{version,formatter}.rb`, run-tests harness, CI).
> This session lands the `Babble::*` skeleton plus P0.3 — the
> lsappinfo parsing fix — with specs. Tier 3 (fresh-clone-no-remote).
>
> Read first:
>
> 1. `AGENTS.md`, `docs/agent-principles.md` (re-read with intent)
> 2. `docs/technical-debt.md` P0.3
> 3. `docs/migration-investigation/01-decisions.md` §§ "W3 component
>    classification" (which units are classes vs modules — follow it
>    exactly), "lsappinfo parsing", "Sorbet typing discipline",
>    "Testing discipline"
> 4. `docs/reviews/pr1-review.md` § B1 (the regex bug this fixes)
> 5. `stash/code-archive/refactor-modular/refactor/ruby/lib/utils/running_gui_bundle_ids.rb`
>    (the prototype's working parser — architectural reference only;
>    do not copy wholesale)
> 6. `cmd/babble/formatter.rb` (Block B's ⨀ helpers — use them for
>    all user-facing output)
>
> **Scope.** Cut `c1-app-manager-skeleton` off `ruby-migration`.
> Land, all under `cmd/babble/` with `# typed: strict`, sigs on
> every method, SPDX via `scripts/annotate.sh`:
>
> 1. `cmd/babble/sh.rb` — `Babble::Sh` module (`class << self`):
>    `capture(*cmd)` returning `{stdout:, stderr:, status:}` struct.
>    Thin wrapper over Homebrew's `system_command` (include
>    `SystemCommand::Mixin`); just enough for C.1's tests.
> 2. `cmd/babble/app_manager.rb` — `Babble::AppManager` class
>    (state-bearing per the classification): constructor takes
>    `config:` (accept `T.untyped` for now; Config lands later).
>    Public: `running_bundle_ids` — parses
>    `/usr/bin/lsappinfo list` output with the corrected pattern
>    (`/^\s*bundleID="(.+?)"/` per P0.3; the prototype's
>    `awk -F'"'` equivalent), de-duped, sorted; returns
>    `T::Array[String]`; on non-zero exit returns `[]` and warns via
>    `Babble::Formatter.opoo`. Stub `quit_app`, `reopen_app` raising
>    `NotImplementedError` (later C-blocks).
> 3. Wire nothing into `cmd/babble.rb`'s `run` yet beyond an
>    optional `--debug`-only diagnostic; the stub banner stays.
> 4. Specs: `test/cmd/babble/sh_spec.rb`,
>    `test/cmd/babble/app_manager_spec.rb` — stub
>    `Babble::Sh.capture` with the fixture; assert ≥ 1 bundle ID
>    parsed, non-`bundleID` lines excluded, duplicates de-duped,
>    non-zero exit → `[]` + warning.
> 5. `test/fixtures/lsappinfo_list_sample.txt` — I will generate
>    this myself with
>    `/usr/bin/lsappinfo list > test/fixtures/lsappinfo_list_sample.txt`
>    and place it in the sandbox clone when you ask; do NOT fabricate
>    it.
> 6. Update `scripts/run-tests.sh` and `ci.yml` hardlink lists for
>    the new files (follow the pattern Block B established).
>
> **Don't:** port phase logic (BrewUpdate/BrewUpgrade/Mas/MacOS);
> touch `bbl`; touch the launcher (C.3, waits on
> `Homebrew::CaskTools::BundleDiscovery` from cask-tools W7); write
> a CHANGELOG.
>
> **Verify before declaring done:** `brew style --changed`,
> `scripts/run-tests.sh`, `reuse lint` all pass (note sandbox
> limitations explicitly if any step can't run).
>
> **End-of-session protocol (Tier 3):** same as Block B — final
> report with branch (`c1-app-manager-skeleton`), commit subjects,
> fetch + re-sign + push + `gh pr create --draft --base
> ruby-migration` procedure. Do not push or open the PR yourself.

After C.1 lands, ask for the C.2 prompt.

---

## Reference: directories that get created and where

| Path | Block | What it holds |
|------|-------|---------------|
| `docs/`, `docs/reviews/`, `docs/migration-investigation/`, `stash/` | done (W2) | planning docs, preserved pre-pivot work |
| `AGENTS.md`, `CLAUDE.md`, `.claude/settings.json`, `docs/agent-principles.md` | 0 | agent context |
| `scripts/sandbox-*.sh` | 0 | Tier 3 isolation scripts |
| `cmd/babble.rb` | B | the external command (stub → orchestrator) |
| `cmd/babble/{version,formatter}.rb` | B | version + ⨀ output helpers |
| `scripts/run-tests.sh` | B | brew-tests hardlink harness |
| `.github/workflows/ci.yml` | B | CI: style + typecheck + brew_tests (`lint.yml`/`actionlint.yml` hand-staged from RF) |
| `adrs.toml`, `docs/decisions/0001–0003` | B | MADR 4.0 ADRs |
| `docs/architecture.md` | B | architecture |
| `cmd/babble/{sh,app_manager}.rb`, `test/` | C.1 | first logic + specs |
| `cmd/babble/{brew_update,brew_upgrade,…}.rb` | C.2+ | phase classes |
| `swift/src/`, `swift/build/` | C (later) | Swift quit alert |
| `.claude/skills/` | after C | skill files |

## When something doesn't fit this plan

This document is the plan as understood after the external-command
pivot. As Blocks 0/B/C unfold, things will change. When that
happens: **update [`technical-debt.md`](technical-debt.md) before
you update the code.** The register is the source of truth; this
handoff document is downstream of it; the code is downstream of
both.

This applies double to Claude Code sessions. If a session reveals
that the assumptions in its handoff prompt are wrong, stop, surface
the issue, update the planning docs, and restart with a corrected
prompt — don't plow through.

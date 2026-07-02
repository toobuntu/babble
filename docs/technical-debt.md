<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Technical debt — babble

> **For preservation of pre-pivot work**, see
> [`migration-investigation/`](migration-investigation/) — the year+ of
> `refactor/modular` work and rationale for the external-command
> pivot.

This is the canonical, prioritized debt register for babble. It covers
three categories of debt: residual ksh debt that won't survive the Ruby
migration anyway (documented for completeness), Ruby migration debt that
PRs #1 and #3 leave behind once their reviews are addressed, and
greenfield gaps that no work to date has touched. Format follows
`homebrew-cask-tools/docs/tech-debt.md` and `blackoutd/docs/reviews/tech-debt-2026.md`.

Priority bands:

- **P0** — blockers for shipping the Ruby migration (v0.6.0). Cannot
  release until these land.
- **P1** — important pre-release polish. Shipping without these is
  defensible if needed but degrades the experience.
- **P2** — architectural / quality improvements. Not blocking, but the
  longer they wait the harder they become.
- **P3** — hygiene and nice-to-haves.

References to PR #1 and PR #3 review findings (B1, S3, etc.) point to
`docs/reviews/pr1-review.md` and `docs/reviews/pr3-review.md`.

---

## P0 — Blockers for v0.6.0

### P0.1 — Cut a fresh `ruby-migration` branch from `main`

PR #1's branch carries enough wrong-as-implemented code (B1, B2, B5, B7
in the PR #1 review) that incremental fixes aren't tractable. The
architecture and the Bash entry point shape are keepers; the rest needs
to be re-derived against tests we control.

**Acceptance criteria:**

- [ ] `ruby-migration` branch exists, cut from `main` after v0.5.2 ships
- [ ] Initial commit imports the conventions stack (P0.2) only — no
      babble logic
- [ ] Subsequent commits address P0.3 onwards in dependency order
- [ ] PR #1 left in place as a reference; not closed until
      `ruby-migration` lands

**Files:** new branch only.

### P0.2 — Land the conventions stack in one commit

Every other piece of work on the new branch should sit on top of the
agent / lint / test / license scaffolding shared with the sister repos.
Doing this once, before any code, prevents the "we'll add tests later"
trap and the "we'll add Sorbet later" trap. Reference templates live in
`homebrew-cask-tools/` and `blackoutd/`.

**Acceptance criteria:**

- [ ] `Gemfile`, `Gemfile.lock` with `sorbet`, `sorbet-runtime`, `rspec`,
      `rubocop`, Homebrew style cops
- [ ] `sorbet/config`, `sorbet/rbi/` after `srb init`
- [ ] `.rspec`, `.rubocop.yml`
- [ ] `LICENSES/GPL-3.0-or-later.txt` and `LICENSES/BSD-2-Clause.txt`
      (matching the sister repos' dual-license approach)
- [ ] `scripts/annotate.sh` — copy from `homebrew-cask-tools` and adapt
- [ ] `.githooks/pre-commit` — `brew style --fix` if available, else
      `rubocop -a` + `shfmt -w`; REUSE compliance check
- [ ] `AGENTS.md`, `CLAUDE.md`, `docs/shared-guidelines.md`,
      `docs/agent-principles.md` — reference the cask-tools versions and
      adapt for babble's domain (no Homebrew tap conventions; this is an
      end-user tool)
- [ ] `docs/architecture.md` — initial draft with module overview, entry
      flow, and config resolution
- [ ] `.github/workflows/` — `ci.yml` with style + sorbet typecheck on
      Ubuntu, `rspec.yml` on `macos-14`, REUSE check, actionlint
- [ ] No babble logic changes in this commit

**Files:** all of the above.

### P0.3 — Fix `running_bundle_ids` regex

Per PR #1 review B1, the regex matches `CFBundleIdentifier` (which
`lsappinfo list` does not emit) instead of `bundleID` (which it does).
Without this fix the entire app-lifecycle feature set is silently
disabled — the headline of the migration delivers nothing.

**Acceptance criteria:**

- [ ] Regex changed to `/^\s*bundleID="(.+?)"/` matching the prototype's
      working version
- [ ] RSpec stubs `lsappinfo list` with a fixture (capture once from a
      real macOS) and asserts the parser returns >= 1 bundle ID and
      excludes lines that don't have `bundleID="..."`
- [ ] Fixture committed as `spec/fixtures/lsappinfo_list_sample.txt`

**Files:** `lib/babble/app_manager.rb`, `spec/babble/app_manager_spec.rb`,
`spec/fixtures/lsappinfo_list_sample.txt`.

### P0.4 — `lsregister -dump` performance: cache and use cheap predicate

Per PR #1 review B2. Current code calls `lsregister -dump` (~20 s) inside
a 0.2 s polling loop; reopening five apps post-upgrade can hang for
tens of minutes. Replace the polling predicate with `osascript -e 'id of
app "<bundle-id>"'` (tens of milliseconds), and cache the
`lsregister -dump` output for the cold-path resolver.

**Acceptance criteria:**

- [ ] `BundleLauncher#app_registered?` uses `osascript -e 'id of app
      "<bundle>"'` for the polling check
- [ ] `BundleLauncher#app_path_via_lsregister_dump` caches the dump for
      the duration of one `Babble` run (instance variable on a small
      `LSRegisterCache` object), not 5 minutes on disk like cask-tools
      does — a single run is short-lived enough that in-process caching
      suffices
- [ ] RSpec covers: cached path used on second call within run; cache
      not used after a fresh `BundleLauncher.new`
- [ ] No regression: reopen of 5 apps completes in < 30 s on a typical
      macOS install (manual smoke test, recorded in
      `spec/manual/TESTING.md`)

**Files:** `lib/babble/bundle_launcher.rb`,
`spec/babble/bundle_launcher_spec.rb`, `spec/manual/TESTING.md`.

### P0.5 — `brew outdated` flags must match `brew upgrade` flags

Per PR #1 review B3. Detection and execution must use the same flags or
the quit/reopen list misses casks the upgrade actually processes.

**Acceptance criteria:**

- [ ] Constant `BREW_OUTDATED_ARGS = %w[--greedy-auto-updates
      --fetch-HEAD]` defined once
- [ ] All four call sites
      (`display_outdated_packages`, `outdated_casks_json`, formulae
      variant, casks variant) pass the same args
- [ ] RSpec covers: constant used in each call site; commands produced
      contain expected flags

**Files:** `lib/babble/brew_upgrade.rb`,
`spec/babble/brew_upgrade_spec.rb`, `lib/babble/constants.rb`.

### P0.6 — Cancel button does not abort the run

Per PR #1 review B4. Clicking Cancel on the unsafe-to-quit dialog should
exclude that cask from the upgrade and continue, not `exit(1)`.

**Acceptance criteria:**

- [ ] `BrewUpgrade#quit_apps` removes the user-vetoed entry from
      `apps_to_manage` and the cask token from the upgrade list
- [ ] `brew upgrade --cask <surviving-tokens>` is invoked instead of
      bare `brew upgrade --cask`
- [ ] The reopen phase skips the vetoed entry
- [ ] `MasUpgrade#quit_apps` mirrors the change
- [ ] RSpec covers: cancel → entry filtered → upgrade list excludes
      token → reopen skipped → other casks proceed normally

**Files:** `lib/babble/brew_upgrade.rb`, `lib/babble/mas_upgrade.rb`,
`spec/babble/brew_upgrade_spec.rb`, `spec/babble/mas_upgrade_spec.rb`.

### P0.7 — Always run `brew update` (or be explicit about skipping it)

Per PR #1 review B5. Drop the silent 1-hour staleness gate. The user
pressed "Run command" and expected it to run.

**Acceptance criteria:**

- [ ] `update_if_needed` either renamed to `update_brew` and always
      runs `brew update --quiet`, or removed entirely
- [ ] If kept: emits a single line on skip ("Skipping `brew update`;
      metadata is N seconds old. Set `BABBLE_FORCE_UPDATE=1` to override.")
- [ ] Exit status of `brew update` checked; warning on failure but
      execution continues to outdated check (which may still have stale
      data, but better than aborting)
- [ ] RSpec covers: success path, failure path with warning, force-skip
      via env var (if gate is kept)

**Files:** `lib/babble/brew_upgrade.rb`,
`spec/babble/brew_upgrade_spec.rb`.

### P0.8 — `quarantine_purger.rb` removed; delegate to `brew purge-quarantine`

Per PR #1 review B7. The `homebrew-cask-tools` `brew purge-quarantine`
command is mature, tested, and tap-distributed. Babble should not ship
its own.

**Acceptance criteria:**

- [ ] `lib/babble/quarantine_purger.rb` deleted
- [ ] `BrewUpgrade` probes for `brew purge-quarantine` once at startup
      (search `brew commands --quiet` output for the command name)
- [ ] If present: invoke per outdated cask after the upgrade phase
- [ ] If absent: emit one-line hint pointing at `brew tap
      toobuntu/cask-tools` and skip
- [ ] README mentions `brew purge-quarantine` as recommended companion
- [ ] RSpec covers: probe positive path → invoked; probe negative path →
      hint emitted, no invocation; cask probe failure → graceful fall
      through

**Files:** delete `lib/babble/quarantine_purger.rb`,
update `lib/babble/brew_upgrade.rb`, update `README.md`,
add `spec/babble/quarantine_delegate_spec.rb`.

### P0.9 — Terminal exclusion implemented in Ruby (replaces PR #3)

Per PR #3 review § "What to keep". The TODO in the README has been there
since v0.5.0; the Ruby migration is the right time to fix it.

**Acceptance criteria:**

- [ ] `lib/babble/terminal_detector.rb` with public API
      `TerminalDetector.running_terminal_cask_token` returning
      `String` or `nil`
- [ ] Detection tiers: `LC_TERMINAL` env, `TERM_PROGRAM` env,
      `__CFBundleIdentifier` env, parent-process walk via libproc or
      `lsof -p`
- [ ] Allowlist of terminal casks (not editors): `iterm2`, `alacritty`,
      `kitty`, `wezterm`, `hyper`, `warp`, `tabby`. Apple Terminal
      detected but mapped to `nil` (no cask)
- [ ] Editors that host terminals (VSCode, VSCodium, Emacs, MacVim) are
      detected and reported on stderr but never returned as exclusions
- [ ] `BrewUpgrade` filters the outdated cask list before invoking
      `brew upgrade --cask`; emits a clear stderr line when exclusion
      fires
- [ ] RSpec covers each detection tier independently with stubbed env
      vars and stubbed process-tree responses; integration spec covers
      the filtering path

**Files:** `lib/babble/terminal_detector.rb`,
`lib/babble/brew_upgrade.rb`, `spec/babble/terminal_detector_spec.rb`,
`spec/babble/brew_upgrade_spec.rb`, `README.md`.

### P0.10 — Sorbet runtime enforced in CI

Per PR #1 review B8. `# typed: strict` magic comments without `srb tc`
in CI is decorative. Enforce.

**Acceptance criteria:**

- [ ] `Gemfile` includes `sorbet` and `sorbet-runtime`
- [ ] `sorbet/config` configured for `strict` files in `lib/`
- [ ] `srb tc` runs cleanly in `.github/workflows/ci.yml` (Ubuntu)
- [ ] All public methods have `sig { ... }` declarations
- [ ] Spec files explicitly use `# typed: false` (Sorbet doesn't play
      well with RSpec mocks)
- [ ] CI fails on Sorbet errors

**Files:** `Gemfile`, `Gemfile.lock`, `sorbet/config`, `sorbet/rbi/*`,
all `lib/babble/*.rb`, `.github/workflows/ci.yml`.

### P0.11 — RSpec test suite with macOS CI runner

Per PR #1 review B8. The migration ships with zero tests. Tests must
land before merge, and macOS-specific behavior must be exercised on a
macOS runner.

**Acceptance criteria:**

- [ ] `spec/spec_helper.rb` with shared setup
- [ ] One `*_spec.rb` per non-trivial module:
      `app_manager_spec.rb`, `bundle_launcher_spec.rb`,
      `brew_upgrade_spec.rb`, `mas_upgrade_spec.rb`,
      `macos_update_spec.rb`, `config_manager_spec.rb`,
      `terminal_detector_spec.rb`, `waiter_spec.rb`
- [ ] `spec/manual/TESTING.md` documents the smoke tests that must be
      run on real hardware (full upgrade cycle, quit/reopen of an
      unsafe-to-quit app, etc.)
- [ ] CI: `rspec.yml` workflow on `macos-14` runner, runs unit specs;
      integration specs that need real macOS APIs (`lsappinfo`,
      `osascript`) gated by an `:integration` tag
- [ ] Ubuntu CI runs unit specs only (with macOS APIs mocked)
- [ ] Coverage target: ≥ 80% on `lib/babble/`. Use `simplecov` to track

**Files:** `spec/`, `.github/workflows/rspec.yml`, `Gemfile`.

### P0.12 — REUSE/SPDX compliance via `scripts/annotate.sh`

Per PR #1 review B8. The PR ships no SPDX headers. License compliance
matters, especially for a GPLv3 project where downstream users need to
know what's covered.

**Acceptance criteria:**

- [ ] `scripts/annotate.sh` adapted from `homebrew-cask-tools`
- [ ] `LICENSES/GPL-3.0-or-later.txt` committed (via `reuse download`)
- [ ] All source files have SPDX headers (Ruby, Bash, Swift, YAML,
      Markdown)
- [ ] Generated/binary files have `.license` sidecars
- [ ] CI runs `reuse lint` and fails on missing headers
- [ ] `.githooks/pre-commit` runs `reuse lint --quiet` on changed files

**Files:** `scripts/annotate.sh`, `LICENSES/`, all source files,
`.github/workflows/ci.yml`, `.githooks/pre-commit`.

### P0.13 — Migrate to `mas outdated --json` (mas v7+)

Agreed in this session as in-scope for v0.6.0. JSON output simplifies
parsing, gives us `bundleID` directly (so users don't have to maintain
it in `apps.yml`), and aligns with the long-term mas API.

**Acceptance criteria:**

- [ ] `mas_upgrade.rb` parses `mas outdated --json` if mas v7+ available
- [ ] Falls back to text parsing on older mas with a one-line warning
- [ ] `mas list --json <app_id>` used to look up display name and
      bundle IDs at runtime, with config-file values as override
- [ ] Spec covers both code paths with fixtures
      (`spec/fixtures/mas_outdated_v7.json`,
      `spec/fixtures/mas_outdated_v6_text.txt`)

**Files:** `lib/babble/mas_upgrade.rb`,
`spec/babble/mas_upgrade_spec.rb`, `spec/fixtures/mas_outdated_*`.

---

## P1 — Important pre-release

### P1.1 — Simplify `bin/babble` portable-Ruby setup

Per PR #1 review S1. Replace `setup-ruby.sh` source with the simpler
`current/bin/ruby` symlink path used by Homebrew's own actions, with
`brew vendor-install ruby` as bootstrap fallback.

**Acceptance criteria:**

- [ ] Probes
      `$(brew --repository)/Library/Homebrew/vendor/portable-ruby/current/bin/ruby`
- [ ] Falls back to `brew vendor-install ruby` and re-probe
- [ ] Final fallback: clear error "portable Ruby not available; please
      run `brew vendor-install ruby` manually"
- [ ] Still loads `brew.env` files in the same order as `bin/brew`
- [ ] No `set -e` / portable-ruby-setup interaction surprises (the
      simpler path doesn't hit the `setup-ruby.sh` failure modes)
- [ ] Smoke test in `spec/manual/TESTING.md`: works on fresh macOS,
      works after `rm -rf $(brew --repository)/Library/Homebrew/vendor/portable-ruby/`,
      works when `command -v brew` resolves to a non-default prefix

**Files:** `bin/babble`, `spec/manual/TESTING.md`.

### P1.2 — Token-to-display-name resolution via `lsappinfo`

Per PR #1 review S2. Stop deriving display names from cask tokens by
capitalize-and-join; pull the actual macOS display name from `lsappinfo
info -only name <bundle-id>`.

**Acceptance criteria:**

- [ ] `AppManager.display_name(bundle_id)` returns the macOS-known name
- [ ] Cached per-run in a hash to avoid duplicate `lsappinfo` calls
- [ ] Falls back to the capitalize-join string if lookup returns empty
- [ ] Used by `quit_apps` and `reopen_apps` for user-visible strings
- [ ] RSpec covers: cached after first call; fallback on empty stdout

**Files:** `lib/babble/app_manager.rb`, `lib/babble/brew_upgrade.rb`,
`lib/babble/mas_upgrade.rb`, `spec/babble/app_manager_spec.rb`.

### P1.3 — Retry loop with bootsnap-cache cleanup

Per PR #1 review S4. Port the ksh `repeat_command` loop to Ruby. This is
one of babble's value-adds beyond raw command sequencing.

**Acceptance criteria:**

- [ ] `Babble::Retry.with_retry(max:, on_fail:) { ... }` helper in
      `lib/babble/retry.rb`
- [ ] `BrewUpgrade` wraps `brew upgrade` invocation in `with_retry`,
      `max: 10`, `on_fail` clears `~/Library/Caches/Homebrew/bootsnap`
- [ ] User-visible message on each retry showing remaining attempts
- [ ] RSpec covers: success on first try (no retry), success on Nth try,
      give-up after max with non-zero exit, on_fail invoked between
      retries

**Files:** `lib/babble/retry.rb`, `lib/babble/brew_upgrade.rb`,
`spec/babble/retry_spec.rb`.

### P1.4 — Config resolution via Homebrew-style lookup chain

Per PR #1 review S5+S6. Repo-shipped `config/apps.yml` becomes
`config/apps.example.yml`; runtime resolution follows env → cwd → repo
root → XDG → home → /etc.

**Acceptance criteria:**

- [ ] `ConfigManager.config_path` resolves in this order:
      `$BABBLE_CONFIG`, `./.babblefile.yml`,
      `<repo>/.babblefile.yml`,
      `${XDG_CONFIG_HOME:-$HOME/.config}/babble/apps.yml`,
      `$HOME/.babblefile.yml`, `/etc/babble/apps.yml`
- [ ] Returns `nil` if no config found; orchestrator handles `nil` as
      "empty config" (no apps to quit)
- [ ] `config/apps.yml` removed from repo; `config/apps.example.yml`
      shipped instead
- [ ] `/config/apps.yml` added to `.gitignore`
- [ ] README documents the lookup order and how to copy the example
- [ ] RSpec covers each tier of the lookup with mocked filesystem

**Files:** `lib/babble/config_manager.rb`, `config/apps.example.yml`
(new), `config/apps.yml` (deleted), `.gitignore`, `README.md`,
`spec/babble/config_manager_spec.rb`.

### P1.5 — `IMPLEMENTATION_SUMMARY.md` removed

Per PR #1 review B9. PR-description text doesn't belong in the tree.

**Acceptance criteria:**

- [ ] `IMPLEMENTATION_SUMMARY.md` deleted
- [ ] Useful technical content migrated into `docs/architecture.md`
      (module overview, entry flow), README (install/usage), and
      `CHANGELOG.md` (per-version highlights)

**Files:** delete `IMPLEMENTATION_SUMMARY.md`, update
`docs/architecture.md`, `README.md`, `CHANGELOG.md`.

### P1.6 — Quit-phase per-bundle sleep removed or replaced

Per PR #1 review S7. The 0.5 s sleep between `osascript quit` calls is
arbitrary. Either drop it or replace with a poll for "app is no longer
running."

**Acceptance criteria:**

- [ ] Either: sleep removed, downstream code tolerates "app may still be
      shutting down" with a short timeout-poll on
      `app.running()` if needed
- [ ] Or: sleep replaced with `wait_until_quit(bundle_id, timeout: 2)`
      that polls `osascript -e "running of app id <id>"` at 0.1 s
      intervals
- [ ] Total time savings on a typical 5-cask run: ≥ 5 s
- [ ] RSpec covers the polling path

**Files:** `lib/babble/app_manager.rb`,
`spec/babble/app_manager_spec.rb`.

### P1.7 — Swift quit_alert: icon path passed as argument

Per PR #1 review S9. Stop embedding base64 icons in `quit_alert.swift`;
pass icon path as second argument.

**Acceptance criteria:**

- [ ] `quit_alert <app_name> <icon_path>` is the new interface; backward
      compatibility not needed (we control all callers)
- [ ] Ruby `AppManager.quit_with_confirmation` resolves the right icon
      (light vs. dark via `defaults read NSGlobalDomain
      AppleInterfaceStyle`) and passes the path
- [ ] Asset updates no longer require recompile
- [ ] Swift source size drops by ~4 KB of base64

**Files:** `swift/src/quit_alert.swift`, `lib/babble/app_manager.rb`,
add `lib/babble/macos_interface/dark_mode.rb` (port from prototype).

### P1.8 — Swift compile failure: graceful osascript fallback

Per PR #1 review S10. If `xcrun swiftc` fails or
xcode-command-line-tools isn't installed, fall back to
`osascript display dialog` for the unsafe-to-quit prompt.

**Acceptance criteria:**

- [ ] `AppManager.ensure_quit_alert_compiled` returns truthy on success,
      `nil` on failure (does not raise)
- [ ] `AppManager.quit_with_confirmation` checks the result; if `nil`,
      falls back to `osascript display dialog "..."` returning the same
      `:approved` / `:cancelled` result
- [ ] User sees a one-line stderr message explaining the fallback once
      per babble run
- [ ] RSpec covers both paths

**Files:** `lib/babble/app_manager.rb`,
`spec/babble/app_manager_spec.rb`.

### P1.9 — Architecture Decision Record: Swift build strategy

Per PR #1 review S10. Record the "no Apple Developer cert →
auto-compile" decision so future readers don't try to ship a binary.

**Acceptance criteria:**

- [ ] `docs/decisions/0001-swift-quit-alert-build-strategy.md` exists,
      following the cask-tools / blackoutd ADR format
- [ ] States: rationale (no Developer cert), tradeoffs, failure modes,
      trigger for revisiting
- [ ] Linked from `docs/architecture.md`

**Files:** `docs/decisions/0001-swift-quit-alert-build-strategy.md`,
`docs/architecture.md`.

---

## P2 — Architectural / quality

### P2.1 — Logger abstraction

Per PR #1 review N2. Standardize on `Babble.info` / `Babble.warn` /
`Babble.debug` so all babble's own messages go to stderr (separable from
brew/mas/softwareupdate output on stdout) and a future `--quiet` /
`--verbose` flag has a single hook.

**Acceptance criteria:**

- [ ] `lib/babble/log.rb` module with the three methods plus level
      control via `BABBLE_LOG_LEVEL` env var
- [ ] All `puts` and `$stderr.puts` calls in `lib/babble/*.rb`
      converted
- [ ] Level filtering tested with RSpec

**Files:** `lib/babble/log.rb` (new), all `lib/babble/*.rb`,
`spec/babble/log_spec.rb`.

### P2.2 — Subprocess wrapper (`Babble::Sh`)

Per PR #1 review N3. Centralize `Open3.capture3` calls behind a small
helper that handles status checking, error formatting, and `--debug`
echo.

**Acceptance criteria:**

- [ ] `lib/babble/sh.rb` with `capture(*cmd)`, `system(*cmd)`,
      `popen3(*cmd) { |io| ... }` shapes
- [ ] All scattered `Open3.capture3` and bare `system` calls replaced
- [ ] Each call site can request `quiet:` (no stderr passthrough),
      `chdir:`, `env:`
- [ ] Debug mode echoes the command (analogous to ksh `set -x`) once
      per call

**Files:** `lib/babble/sh.rb` (new), all `lib/babble/*.rb`,
`spec/babble/sh_spec.rb`.

### P2.3 — DRY ConfigManager validation

Per PR #1 review S11. Two near-identical validation branches collapse
into one helper.

**Acceptance criteria:**

- [ ] `validate_entry(entry, kind:, identifier_key:)` private helper
- [ ] Both `homebrew` and `mas` branches call it
- [ ] Same validation errors, same conflicts, same structural issue
      messages preserved
- [ ] RSpec covers: both kinds work; conflict detection works for both

**Files:** `lib/babble/config_manager.rb`,
`spec/babble/config_manager_spec.rb`.

### P2.4 — `BrewUpgrade#display_outdated_packages` split into query/print

Per PR #1 review S13. The method does both query and presentation;
splitting them improves testability and allows callers to inspect the
data structure before deciding to print.

**Acceptance criteria:**

- [ ] `outdated_summary` returns `{formulae: [...], casks: [...]}` (or a
      Sorbet `T::Struct`)
- [ ] `print_outdated_summary(summary)` handles presentation
- [ ] `summary.empty?` replaces the boolean return
- [ ] RSpec exercises the structure separately from the printer

**Files:** `lib/babble/brew_upgrade.rb`,
`spec/babble/brew_upgrade_spec.rb`.

### P2.5 — `script/syntax` and `script/style` learn Ruby

Per PR #1 review N4. Bring Ruby into the lint/syntax pipeline as a
first-class citizen, not a parse-only afterthought.

**Acceptance criteria:**

- [ ] `script/style` runs `rubocop` on `lib/babble/*.rb` and
      `spec/**/*.rb`
- [ ] `script/style --fix` runs `rubocop -a`
- [ ] `script/syntax` runs `srb tc` (or notes "Sorbet not configured" if
      not yet)
- [ ] CI workflows updated to call these scripts (currently they only
      run inline `shfmt`/`shellcheck`)

**Files:** `script/style`, `script/syntax`, `.github/workflows/ci.yml`.

### P2.6 — Skill files in `.claude/skills/`

The cask-tools and blackoutd repos use Claude Code skill files for
common workflows (`dev-cycle`, `release-check`, `review-pr`, `test`).
Babble should adopt the same pattern.

**Acceptance criteria:**

- [ ] `.claude/skills/dev-cycle/SKILL.md` — local dev loop (write code,
      run rubocop, run rspec, commit)
- [ ] `.claude/skills/release-check/SKILL.md` — pre-release checklist
- [ ] `.claude/skills/review-pr/SKILL.md` — PR review process
- [ ] `.claude/skills/test/SKILL.md` — running specs locally and in CI
- [ ] `.claude/settings.json` configured for the project's MCP servers

**Files:** `.claude/skills/`, `.claude/settings.json`.

### P2.7 — `.github/copilot-instructions.md`

The cask-tools and blackoutd repos have explicit instructions for the
Copilot coding agent that go beyond AGENTS.md (which is the IDE-side
instructions). Babble should add the same.

**Acceptance criteria:**

- [ ] `.github/copilot-instructions.md` exists
- [ ] Cross-references `AGENTS.md`, `docs/shared-guidelines.md`
- [ ] Documents the macOS-on-Ubuntu-runner constraint
- [ ] Lists the pre-installed tools available in the Copilot sandbox

**Files:** `.github/copilot-instructions.md`.

### P2.8 — `ROADMAP.md` and `CHANGELOG.md`

Babble lacks both. ROADMAP keeps the multi-month vision visible; CHANGELOG
keeps the per-release deltas in the tree.

**Acceptance criteria:**

- [ ] `ROADMAP.md` lists the v0.6 / v0.7 / v1.0 milestones and the rough
      shape of each
- [ ] `CHANGELOG.md` follows Keep a Changelog format
- [ ] `script/release-notes` updated to source from `CHANGELOG.md`
      [Unreleased] section

**Files:** `ROADMAP.md`, `CHANGELOG.md`, `script/release-notes`.

---

## P3 — Hygiene

### P3.1 — `archive/` cleanup

Once the Ruby migration lands, the `archive/babble/` and
`archive/_usr_local_bin_bbl` files no longer have working-reference
value. Either move them to a `babble-archive` orphan branch, or delete.
Document the decision.

**Acceptance criteria:**

- [ ] `archive/` removed from `main` after `ruby-migration` lands
- [ ] Content preserved in a separate orphan branch (e.g.
      `archive/legacy-prototypes`) for reference
- [ ] `docs/decisions/00NN-archive-strategy.md` records the decision

**Files:** `archive/` (deleted), new orphan branch,
`docs/decisions/00NN-archive-strategy.md`.

### P3.2 — Demo SVG regeneration

`assets/demo-241211-2018-x2.svg` is from December 2024 and shows the ksh
output. After the Ruby migration, regenerate to show the new output.

**Acceptance criteria:**

- [ ] New demo SVG generated using `asciinema` + `svg-term-cli`
      (workflow same as the current one; document in
      `docs/architecture.md` § "regenerating the demo")
- [ ] Old SVG either replaced or kept alongside (with date in filename)
- [ ] README updated if filename changes

**Files:** `assets/demo-2026MM-DD-x2.svg`,
`docs/architecture.md`, `README.md`.

### P3.3 — `tput` retention comment in `waiter.rb`

Per PR #1 review N6. Add a one-line comment explaining the deliberate
departure from `tput` in the ksh original.

**Acceptance criteria:**

- [ ] Comment in `waiter.rb` near the ANSI escape definitions
- [ ] Mentions: Ruby has no `tput` binding; values are stable; shelling
      out per-call is wasteful

**Files:** `lib/babble/waiter.rb`.

### P3.4 — Dependabot scope expansion

Current `.github/dependabot.yml` watches only GitHub Actions. Add Bundler
once `Gemfile` exists.

**Acceptance criteria:**

- [ ] `dependabot.yml` includes a `bundler` ecosystem entry
- [ ] Both ecosystems use the same `groups: all` pattern as actions
- [ ] CI passes with grouped Dependabot PRs

**Files:** `.github/dependabot.yml`.

### P3.5 — `script/log-since-latest-tag` and `script/release-notes` Ruby port

Both scripts are 100+ line Bash with embedded awk. Port to Ruby once the
Ruby toolchain is set up; consolidate into a single
`script/release-tooling.rb` with subcommands. Lower priority — they
work — but the duplication and the awk pipelines are a maintenance
hazard.

**Acceptance criteria:**

- [ ] `script/release-tooling.rb` with `log` and `notes` subcommands
- [ ] Existing Bash scripts deprecated (kept temporarily as shim →
      `exec` to Ruby) and eventually deleted
- [ ] Functional parity verified against current behavior

**Files:** `script/release-tooling.rb` (new), `script/log-since-latest-tag`
(deprecate), `script/release-notes` (deprecate).

### P3.6 — README modernization

The current README still describes babble as "written in shell" and
points at the v0.5 ksh download path. After v0.6 ships, refresh.

**Acceptance criteria:**

- [ ] "Written in shell" → "written in Ruby with a Bash wrapper"
- [ ] Install path covers cloning the repo (the entry script needs
      sibling files)
- [ ] Configuration section points at `~/.config/babble/apps.yml` and
      links to `config/apps.example.yml`
- [ ] Mentions `brew purge-quarantine` as a recommended companion
- [ ] Includes a small "what babble does NOT do" section (no
      auto-restart of CLI tools, no headless mode, requires GUI session)
- [ ] Tabler Icons attribution preserved

**Files:** `README.md`.

### P3.7 — `.shellcheckrc` review

The current rules predate the Ruby migration. After the Bash surface
shrinks to `bin/babble` + `script/*`, review for relevance.

**Acceptance criteria:**

- [ ] Each enabled rule confirmed still relevant given the smaller
      Bash surface
- [ ] Any new rules useful for `bin/babble` added
- [ ] `script/style` exits 0 with no warnings on a clean tree

**Files:** `.shellcheckrc`.

---

## Legacy ksh debt (decommissioned with v0.6.0)

These items were debt against the ksh `bbl` script. They are recorded
here for completeness; they do not need to be addressed because the
Ruby migration replaces the ksh script wholesale. If for any reason the
migration is delayed past 2026-Q3, revisit.

- **L1.** ~700 lines of nested `# NOTE:` and `# TODO:` comments in the
  bbl header, capturing 2+ years of design exploration. Replaced by
  proper docs/decisions/ ADRs.
- **L2.** Hardcoded `restart_list_brew` and `restart_list_mas` arrays
  with the maintainer's personal app list. Replaced by user-config YAML.
- **L3.** Two associative arrays (`brew_token_bundle_array`,
  `mas_appid_bundle_array`) duplicating the data above. Replaced by
  config schema.
- **L4.** `repeat_command` / `fallback_commands` inline functions
  defined inside the main control flow. Replaced by `Babble::Retry`
  module.
- **L5.** `comm`-based set operations across temporary files for
  computing the "running and on-watchlist" intersection. Replaced by
  Ruby `Array#&` / `Set` operations.
- **L6.** Inlined awk scripts for parsing `brew update` output to
  detect new formulae/casks/release notes. Replaced by structured
  parsing in `BrewUpdate` module (still TODO; the prototype's
  `brew_update.rb` had a working version).
- **L7.** ANSI escape sequence construction via `tput setaf` in
  subshells, computed once at script start. Replaced by inline ANSI
  literals in `Waiter`.
- **L8.** Trap on SIGINT for graceful exit. Replaced by Ruby's default
  `SignalException` handling, with explicit handling in `Waiter`.
- **L9.** `set -x` / `{ set +x; }` blocks for command tracing
  transparency. Replaced by `Babble::Sh` debug mode.
- **L10.** Mixed quote styles, mixed `test` vs `[[` vs `[`,
  inconsistent function declarations (`function foo {` vs `foo() {`).
  Lint cleanup not relevant post-migration.

---

## Tracking

Each item should be filed as a GitHub issue on `toobuntu/babble` with
the appropriate label (`P0`, `P1`, `P2`, `P3`, `legacy-ksh`). Issues
should reference this document by section heading. PRs that close
issues should reference the issue number and update this document if
the acceptance criteria change.

When a P0 item lands, mark it [done] inline rather than removing it —
the audit trail of what shipped at v0.6.0 is more valuable than a
clean current list. Periodically (e.g. at each minor version) compact
completed items into a "Done in vX.Y" appendix at the bottom.

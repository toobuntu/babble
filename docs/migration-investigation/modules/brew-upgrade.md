<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# BrewUpgrade

## Purpose

The main upgrade orchestration phase. Discovers outdated
formulae and casks, identifies which casks correspond to
running apps that need quit/reopen, quits them, runs
`brew upgrade`, reopens them. Plus retry-on-failure with
bootsnap-cache cleanup.

## Refactor/modular implementation

`refactor/ruby/lib/brew_upgrade.rb` (~700 lines including
extensive commented-out alternative implementations).
The complete file is preserved at
`code-archive/refactor-modular/lib/brew_upgrade.rb`.

Top-level flow (`run_upgrade_process`):

1. Run validation tests (bundle ID and Homebrew token regex
   self-tests)
2. `reorganize_config_file` — sort and dedup-check the
   config via yq
3. `load_and_validate_configuration` — parse YAML, validate,
   report conflicts/structural issues
4. `update_if_needed` — delegates to `brew update-if-needed`
5. `display_outdated_packages` — prompts user before running
   `brew outdated`; early-exit if nothing's outdated
6. `outdated_casks_json` — fetch JSON list of outdated cask
   tokens
7. `set_running_apps` — list currently-running app bundle IDs
8. Compute `casks_to_quit_and_reopen` — intersection of:
   - cask is in user's `apps.homebrew[]` config
   - cask is in `outdated_cask_tokens`
   - cask has `bundle_ids` field that's an array
   - at least one of the bundle IDs is in `initially_running_apps`
9. `quit_apps` — JXA-quit each running bundle ID
10. `upgrade_packages` — run `brew upgrade
    --greedy-auto-updates --fetch-HEAD --display-times`
11. `reopen_apps` — relaunch each previously-running bundle ID
    via `BundleLauncher.launch`
12. Print summary

Critical sub-methods:

- `valid_homebrew_token?` — regex includes `(@[a-z0-9.-]+)?`
  for pinned versions like `python@3.12`, `node@nightly`
- `valid_bundle_id?` — regex matches Apple's CFBundleIdentifier
  spec
- `validate_config` — produces 4-tuple
  `(valid_config, conflicts, validation_errors, structural_issues)`
- `reorganize_config_file` — yq-based sort + duplicate
  detection
- `outdated_casks_json` — uses `brew outdated --greedy-auto-updates
  --fetch-HEAD --json=v2`
- `quit_app` — JXA-based (full script in [`app-manager.md`](app-manager.md))
- `set_running_apps` — `lsappinfo list | awk -F'"' '/bundleID/{print $2}'`

## Design ideas that survive the pivot

- The phase orchestration shape (validate → update → outdated
  → identify-quit-set → quit → upgrade → reopen → summary)
- Homebrew token validation including pinned versions
- yq-based (or, in W3, pure-Ruby) config sort + dedup
- JXA quit
- lsappinfo+awk for running apps
- `brew outdated --json=v2` parsing for the outdated cask list
- `brew upgrade --greedy-auto-updates --fetch-HEAD
  --display-times` flags
- The `casks_to_quit_and_reopen` intersection logic
- Delegation to `BundleLauncher` for reopen

## Design ideas that don't survive

- The 200+ lines of commented-out alternative implementations
  at the bottom of `run_upgrade_process`. Git history is
  preservation; new file starts clean.
- The `reorganize_config_file` shelling out to `yq` for
  auto-reorganize-on-startup. W3 makes reorganize an
  explicit subcommand (`babble reorganize`); the
  comment-preservation problem still requires yq, just on
  user demand. See [`../01-decisions.md`](../01-decisions.md)
  § "yq-based config sorting and dedup detection" for the
  psych-pure-unavailable-in-third-party-taps rationale.
- The `update_if_needed = system("brew", "update-if-needed")`
  call. As an external command, this becomes
  `safe_system HOMEBREW_BREW_FILE, "update-if-needed"` per
  Homebrew/brew's AGENTS.md guideline.
- Direct API calls to `Homebrew::Cmd::Upgrade.new(...).run`
  for action invocation. Use
  `safe_system HOMEBREW_BREW_FILE, "upgrade", *args` instead.
  Read state via Ruby APIs (`Formula.installed`,
  `Cask::Caskroom.casks`); mutate state via `safe_system
  HOMEBREW_BREW_FILE`.
- The pre-confirmation "Upgrading X..." messages. See
  [`../03-known-bugs-and-rough-edges.md`](../03-known-bugs-and-rough-edges.md)
  § "Confirmation prompt phrasing redundancy".
- The doubled `Upgrade process complete / Reopened
  necessary applications` ordering. Same file.

## Bugs / blockers found

PR #1's BrewUpgrade equivalent had several issues — see
`../reviews/pr1-review.md` § B1 (broken regex breaks app
detection), § B5 (cancel button exits run), § B6 (brew
outdated/upgrade flag mismatch), § B7 (silent skip of
brew update).

Refactor/modular's version doesn't have these specific bugs.
The retry-with-bootsnap-cleanup loop from the original ksh
is not ported (see `../03-known-bugs-and-rough-edges.md` §
"Retry-with-bootsnap-cleanup not ported").

## What feeds W3

- The full ~700-line refactor/modular implementation as
  baseline (with the commented-out blocks dropped)
- The phase orchestration with refined message wording
- The retry-with-bootsnap-cleanup pattern from the ksh,
  ported as `Babble::Retry.with_retry`
- Direct `brew outdated --json=v2` parsing replaced by
  Homebrew API calls (`Cask.outdated_casks`, `Formula.outdated`)
- The new schema's `bundle_ids.{quit, reopen}` distinction
  changes the `casks_to_quit_and_reopen` intersection slightly:
  the "quit" set is union of `quit` lists from running apps;
  the "reopen" set is union of `reopen` lists from
  previously-running apps

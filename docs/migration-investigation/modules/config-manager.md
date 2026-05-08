<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# ConfigManager

## Purpose

Loads, validates, and (in refactor/modular) reorganizes the
unified-config.yml file that lists the user's apps with their
bundle IDs and per-app metadata (`unsafe_to_quit`,
`quit_message`).

This is the centerpiece of babble's "declarative config" —
the user maintains a YAML file describing the apps they want
babble to manage; babble reads it at startup and uses it
throughout the run.

## Refactor/modular implementation

There is no dedicated `config_manager.rb` in
refactor/modular's `lib/`. The configuration logic lives
inline in `BrewUpgrade`:

- `load_and_validate_configuration(config_file)` —
  load + validate + report
- `validate_config(raw_config)` — produces 4-tuple
  `(valid_config, conflicts, validation_errors, structural_issues)`
- `check_duplicates(data)` — detects duplicate tokens or
  app_ids
- `reorganize_config_file(file_path)` — yq-based sort + dedup

Plus several iterations in `refactor/ruby/devel/config/`:

- `config_loader.rb` — minimal loader
- `loader-v2.rb`, `loader.rb` — more elaborate loaders (~200
  lines each)
- `reorganizer.rb`, `reorganizer.rb.bak` — yq-based reorganizer
- `config_merge.rb` — handling of conflicts via merging

The schema is `unified-config.yml`:

```yaml
apps:
  homebrew:
    - token: <cask_token>
      bundle_ids:
        - <CFBundleIdentifier>
      unsafe_to_quit: <bool>
      quit_message: <string>
  mas:
    - app_id: <integer>
      name: <string>
      bundle_ids:
        - <CFBundleIdentifier>
      unsafe_to_quit: <bool>
      quit_message: <string>
```

A TODO comment at the top of `unified-config.yml` flags the
asymmetric-bundle_ids problem (Adobe Acrobat case).

## Design ideas that survive the pivot

- The `apps.homebrew[]` and `apps.mas[]` array structure
- The per-entry fields: `token` / `adam_id`, `bundle_ids`,
  `unsafe_to_quit`
- The validation phase that produces structured
  errors/conflicts (rather than just raising on first issue)
- The Brewfile-style upward-walk lookup chain for the file
  location (now properly implemented in W3 per
  [`../01-decisions.md`](../01-decisions.md))
- Duplicate detection (independent of yq; works with stdlib
  Psych)
- **Auto-reorganize-on-startup via yq.** Kept; yq becomes
  a runtime dependency declared in babble's Homebrew formula.
  See [`../adrs/0002-yaml-handling-yq-vs-psych-vs-psych-pure.md`](../adrs/0002-yaml-handling-yq-vs-psych-vs-psych-pure.md)
  for the rationale.
- **Multi-file merge with conflict reporting**, fully
  implemented in `devel/config_merge.rb`,
  `devel/config/loader.rb`, and `devel/config/loader-v2.rb`
  (never promoted to `lib/`). The design loads configs from
  multiple priority-ordered locations, deep-merges them with
  field-aware semantics (set union for `bundle_ids`, logical
  OR for `unsafe_to_quit`, higher-priority-wins for
  `quit_message`/`name`), and reports conflicts. W3 promotes
  this to `Babble::Config::Merger`. See
  [`../01-decisions.md`](../01-decisions.md) § "Multi-file
  config merge with conflict reporting" for refinements
  (quieter conflict reporting, schema migration, validate-
  then-merge ordering, cache management).

## Design ideas that don't survive

- The schema's flat `bundle_ids: [list]` form (problem case:
  apps with helpers like Adobe). W3 adopts
  `bundle_ids.{quit, reopen}` per
  [`../01-decisions.md`](../01-decisions.md). The flat-list
  shorthand still works (normalizes to `quit` and `reopen`
  both equal to the flat list); the structured form handles
  helpers.
- `app_id` field name. W3 renames to `adam_id` to align
  with mas's terminology (and avoid the historical
  app_id/bundle_id confusion).
- `unified-config.yml` filename. W3 renames to
  `babble.apps.yml` (namespaced, descriptive).
- **Flat sibling fields for `quit_message`, `gui_confirm`,
  etc.** W3 nests these under a single `quit_handling` key
  alongside `unsafe_to_quit`. The boolean stays at top level
  as the primary signal; the elaboration nests:
  ```yaml
  unsafe_to_quit: true
  quit_handling:
    confirm: gui                 # gui | terminal | silent
    quit_message: "..."          # optional override
    timeout_seconds: 30          # optional
  ```
  See [`../01-decisions.md`](../01-decisions.md) for the full
  schema.
- **Configuration logic embedded in `BrewUpgrade`.** W3
  promotes to a proper module triple:
  - `Babble::Config::Loader` — finds the file via lookup
    chain, parses YAML, returns raw hash
  - `Babble::Config::Validator` — takes raw hash, returns
    a value object `(valid_config, errors, warnings,
    conflicts)`
  - `Babble::Config::Reorganizer` — takes valid_config,
    sorts and dedupes via yq, writes back to file
  These compose: `Config.load(path)` calls Loader →
  Validator → Reorganizer in sequence at startup. Pieces are
  independently testable.
- The broken `quit_message` validation block. See
  `../03-known-bugs-and-rough-edges.md` § "Quit_message
  handling block has duplicate logic".
- The hardcoded config path (`unified-config.yml` in the
  current dir). Replaced by the lookup chain.

## Bugs / blockers found

- Quit_message validation block is broken (variables not
  assigned). See `../03-known-bugs-and-rough-edges.md`.
- The `validate_config` method returns a 4-tuple whose
  consumer doesn't always use all four elements. Refactor in
  W3 to a proper `ValidationResult` value object.

PR #1's config handling was a single-tier shell-out to
`brew config` then YAML.load, which is a regression. See
`../reviews/pr1-review.md` § B (config handling section).

## What feeds W3

- The schema with the new `bundle_ids.{quit, reopen}`,
  `adam_id`, `unsafe_to_quit` + `quit_handling` shape
- The new filename `babble.apps.yml`
- The split `Babble::Config::{Loader, Validator, Merger,
  Reorganizer}` quartet with public APIs:
  - `Config.load(path = nil)` — uses lookup chain if path nil;
    composes Loader → Validator → Merger → Reorganizer
  - `Config#valid?`, `#errors`, `#warnings`, `#conflicts`
  - `Config#homebrew_entries`, `#mas_entries`
- Multi-file merge via `Config::Merger`, with conflict
  reporting collapsed to one warning per app (vs.
  refactor/modular's one warning per field per duplicate key)
- Auto-reorganize via `Config::Reorganizer` shelling out to
  yq (preserves comments)
- Real RSpec specs (the validation tests in
  refactor/modular's `BrewUpgrade.test_valid_*` methods become
  spec examples, and `devel/config/loader.rb`'s merge logic
  becomes spec examples for `Merger`)
- Sorbet sigs throughout

<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# MasUpgrade

## Purpose

Mac App Store upgrade phase. Lists outdated MAS apps via
`mas outdated`, identifies which correspond to running apps
that need quit/reopen (parallel to BrewUpgrade's logic for
casks), quits them, runs `mas upgrade`, reopens.

## Refactor/modular implementation

`refactor/ruby/devel/mas_upgrade-v1.rb` (~669 lines, in the
devel/ subdirectory rather than lib/, indicating not-yet-finished
status). The file is preserved at
`code-archive/refactor-modular/devel/mas_upgrade-v1.rb`.

The implementation predates mas v7's JSON support, so it parses
text output from `mas outdated`:

```ruby
# Approximate (the file is in devel/ and somewhat aspirational)
def self.outdated_mas_apps
  stdout, status = Open3.capture2("mas outdated")
  return [] unless status.success?
  # Parse text output: each line is "<app_id>  <name>  (<old> -> <new>)"
  stdout.lines.map { |line| line.match(/^(\d+)/)&.[](1) }.compact
end
```

The mas-token-generator subcommand
(`refactor/ruby/utils/mas_token_generator.rb`) was a separate
utility for generating the bundle ID for a given app ID.

## Design ideas that survive the pivot

- The phase orchestration paralleling BrewUpgrade (outdated
  → quit → upgrade → reopen)
- The bundle-id-driven mapping (apps.mas[].bundle_ids in config)
- The asymmetric quit/reopen for mas helpers (same as casks)
- The `unsafe_to_quit: true` confirmation flow

## Design ideas that don't survive

- **Text parsing of `mas outdated` output.** mas v7 introduced
  `--json` for `list`, `outdated`, `info`, `lookup`, `search`,
  `config`. Use it. `mas outdated --json` returns structured
  data:
  ```json
  [
    {
      "appId": 1595464182,
      "name": "MonitorControlLite",
      "bundleID": "app.monitorcontrol.MonitorControlLite",
      "version": "1.5.5",
      "newVersion": "1.5.6"
    }
  ]
  ```
- **`mas_token_generator.rb` as a separate utility.** mas v7's
  `mas info <app_id> --json` provides everything the generator
  was computing, authoritatively. Drop the generator.
- **The aspirational nature of mas_upgrade-v1.rb.** It lived
  in devel/ rather than lib/ because it wasn't fully wired up.
  W3 implements it cleanly from the start.

## Bugs / blockers found

mas itself had its own issues with text parsing — the bundle
ID wasn't always available without a separate `mas info`
call. v7's JSON output makes this trivial. No babble-specific
bugs to document.

## What feeds W3

- The phase shape (outdated → identify-quit-set → quit
  → upgrade → reopen)
- The new `bundle_ids.{quit, reopen}` schema applies the same
  way to mas apps as to casks
- The mas v7 JSON parsing replaces all the text-parsing
  fragility
- Direct shell-out to `mas` (mas is not a Homebrew internal,
  so this stays a shell-out via SystemCommand::Mixin or Open3)
- The mas-token-generator gets dropped

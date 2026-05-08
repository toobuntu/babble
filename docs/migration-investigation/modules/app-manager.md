<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# AppManager

## Purpose

Manages the lifecycle of GUI applications around upgrades:
detecting which apps are running, quitting them before
upgrades that would otherwise produce undefined behavior,
and reopening them afterward. The orchestrator for
`bundle_launcher` (launching) and the JXA quit logic.

In refactor/modular, this responsibility was split between
methods in `BrewUpgrade` (`set_running_apps`, `quit_app`,
`open_app`) and a separate `MacUtils::BundleLauncher` for
the launch path. The W3 rewrite consolidates these into a
single `Babble::AppManager` module with a clean public API.

## Prototype implementation (`archive/babble/ruby/refactor/ruby/lib/utils/running_gui_bundle_ids.rb`)

The `archive/` directory has a small standalone version:

```ruby
require "open3"

module Utils
  module RunningGuiBundleIds
    def self.list
      stdout, status = Open3.capture2(
        "/usr/bin/lsappinfo list | " \
        "/usr/bin/awk -F'\"' '/bundleID/{print $2}' | " \
        "/usr/bin/sort -u",
      )
      return [] unless status.success?
      stdout.strip.empty? ? [] : stdout.split("\n").compact
    end
  end
end
```

This is just the running-app detection piece. The quit and
reopen pieces lived in `BrewUpgrade` in the prototype.

## Refactor/modular implementation

In `refactor/ruby/lib/brew_upgrade.rb` the relevant methods
are scattered: `set_running_apps`, `quit_app`,
`handle_quit_result`, `open_app`. Plus `MacUtils::BundleLauncher`
in `refactor/ruby/lib/utils/bundle_launcher.rb` for the launch
fallback chain.

Key surviving design ideas:
- **JXA over osascript -e** for quit (proper exception
  handling, structured output)
- **lsappinfo with awk-based parsing** for running-app
  detection (the working pattern, not the broken
  `CFBundleIdentifier=` regex from PR #1)
- **Custom `OpenLaunchError` class** with `to_h` for
  diagnostics (lives in BundleLauncher; re-exported by
  AppManager in W3)

Quit invocation uses JXA (excerpt):

```ruby
jxa_script = <<-EOS
  var app;
  try {
      var app = Application("#{bundle_id}");
      if (app.running()) {
          app.quit();
          $.NSFileHandle.fileHandleWithStandardOutput.writeData(
              $.NSString.alloc.initWithUTF8String("Successfully quit application with Bundle ID: #{bundle_id}.\\n").dataUsingEncoding($.NSUTF8StringEncoding)
          );
      } else {
          // ...
      }
  } catch (error) {
      // ...
  }
EOS

stdout, stderr, = Open3.capture3("osascript -l JavaScript", stdin_data: jxa_script)
```

## Design ideas that survive the pivot

- JXA-based quit (over osascript-tell)
- lsappinfo + awk-based running-app detection
- The bundle-id-to-cask mapping driven by config (apps.yml's
  `bundle_ids` field per token)
- Pre-quit-confirmation dialog for `unsafe_to_quit: true`
  casks (the Swift `quit_alert` invocation)
- Custom error classes for structured failure handling

## Design ideas that don't survive

- Splitting these methods across multiple modules.
  W3 consolidates into `Babble::AppManager` with a clean
  public API: `running_bundle_ids`, `quit_app`, `reopen_app`,
  `quit_with_confirmation`. The fallback launcher logic
  (BundleLauncher) becomes a private helper or stays as a
  separate module that AppManager consumes.
- Returning `true`/`false` from `quit_app` based on string
  matching of stdout. W3 uses proper exception classes.

## Bugs / blockers found

See `../reviews/pr1-review.md` § B1 (the broken regex), § B2
(lsregister polling), § B5 (unsafe_to_quit confirmation
unreached because B1 broke detection).

## What feeds W3

- The JXA script template (port verbatim, just adjust
  invocation idiom for SystemCommand::Mixin)
- The lsappinfo+awk pattern (the current code in
  refactor/modular's `set_running_apps`)
- The bundle-id-driven mapping (combined with the
  `bundle_ids.{quit, reopen}` schema decision in
  `01-decisions.md`)
- Custom error class shape (carry `OpenLaunchError` design
  forward, possibly renamed to `Babble::AppManager::Error`)

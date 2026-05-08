<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# DisplayAlert

## Purpose

Ruby orchestrator that invokes the Swift `quit_alert` binary
to show a confirmation dialog before quitting an
`unsafe_to_quit: true` app. Detects dark/light mode (via
`DarkMode.enabled?`), picks the right icon, detects host
architecture (arm64 vs x86_64), and runs the
architecture-specific binary.

The Swift binary itself is the actual quit-alert dialog with
"Continue" and "Cancel" buttons. DisplayAlert is the Ruby
wrapper that tells it what to display.

## Refactor/modular implementation

`refactor/ruby/lib/macos_interface/display_alert.rb` (~100
lines). Preserved at
`code-archive/refactor-modular/lib/macos_interface/display_alert.rb`.

```ruby
require "rbconfig"
require_relative "dark_mode"

module MacOSInterface
  class DisplayAlert
    COMMAND_DIR = File.expand_path("../../../swift/build/dist", __dir__).freeze
    ICON_DIR = File.expand_path("../../../assets", __dir__).freeze
    ICONS = {
      light: "#{ICON_DIR}/refresh-dot-dark.svg".freeze,
      dark:  "#{ICON_DIR}/refresh-dot-light.svg".freeze,
    }.freeze

    def self.quit_alert(app_name)
      validate_app_name(app_name)
      display_alert(app_name)
    end

    # ... validation methods ...

    def self.icon_path
      MacOSInterface::DarkMode.enabled? ? ICONS[:dark] : ICONS[:light]
    end

    def self.detect_architecture
      case RbConfig::CONFIG["host_cpu"]
      when "x86_64"
        "x86_64"
      when "aarch64"
        "arm64"
      else
        raise "Unsupported architecture detected: #{RbConfig::CONFIG["host_cpu"]}"
      end
    end

    def self.display_alert(app_name)
      validate_icon_files
      icon = icon_path
      architecture = detect_architecture
      command = "#{COMMAND_DIR}/quit_alert_#{architecture} #{app_name} #{icon}"
      system(command) ? true : false
    end
  end
end
```

The Swift binary is invoked with `<app_name>` and `<icon_path>`
as arguments. Its exit code determines the user's choice:
0 = continue, non-zero = cancel.

There are also `display_alert.rb` versions in
`refactor/ruby/devel/` from various iterations.

## Design ideas that survive the pivot

- The orchestrator pattern: Ruby wraps a Swift binary that
  does the actual GUI dialog
- Light/dark icon selection via `DarkMode.enabled?`
- Architecture detection via `RbConfig::CONFIG["host_cpu"]`
- The exit-code-as-choice convention (0 = continue,
  non-zero = cancel)
- Validation of icon file presence before invoking

## Design ideas that don't survive

- **Pre-built architecture-specific binaries shipped in repo.**
  W3 auto-compiles via `xcrun swiftc` on first run.
  See `adrs/0001-swift-quit-alert-build-strategy.md` for the
  full ADR.
- **The `MacOSInterface::DisplayAlert` namespace.** Collapses
  to `Babble::QuitAlert` or `Babble::DisplayAlert`.
- **Hardcoded `swift/build/dist/`** path. W3 looks for the
  compiled binary at a cache location
  (`$XDG_CACHE_HOME/babble/swift/quit_alert_<arch>` or similar);
  if absent, compiles it.
- **`system(command_string)`** with shell-string composition
  (vulnerable to special characters in app_name). W3 uses
  array-form invocation.

## Bugs / blockers found

The pre-built binary approach silently works for the
maintainer's local development but fails for distribution
(no Apple Developer cert → no codesign → Gatekeeper rejection
on Apple Silicon). This was the main motivation for the
auto-compile pivot in W3.

PR #1 figured out the auto-compile approach (this is one
piece PR #1 got right).

## What feeds W3

- The Ruby-orchestrator-of-Swift-binary pattern
- The light/dark icon decision (consume `Babble::Formatter.dark_mode_enabled?`)
- The architecture detection
- Auto-compile-on-first-run via `xcrun swiftc` per the ADR
- Graceful fallback to `osascript display dialog` if
  xcode-command-line-tools is unavailable
- Final fallback: skip the prompt entirely, just quit the app
  (lossy but doesn't block the upgrade workflow)

## Relationship to terminal exclusion

If the app being quit is the terminal that babble is running
in, the Swift quit_alert can't help — quitting babble's host
terminal would terminate babble mid-run. This is detected by
the `TerminalDetector` module (separate concern,
[`terminal-detector.md`](terminal-detector.md)) and the app
is excluded from quit/reopen entirely.

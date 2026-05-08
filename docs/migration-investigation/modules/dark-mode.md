<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# DarkMode

## Purpose

Detects whether the user's macOS appearance is set to dark
mode. Used by `DisplayAlert` to choose the correct icon
variant (light or dark) when invoking the Swift `quit_alert`
binary.

A small, self-contained helper.

## Refactor/modular implementation

`refactor/ruby/lib/macos_interface/dark_mode.rb` (full file,
~44 lines including header):

```ruby
# typed: strict
# frozen_string_literal: true

require "open3"

module MacOSInterface
  class DarkMode
    def self.enabled?
      stdout, status = Open3.capture2(
        "defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null"
      )
      status.success? && stdout.strip == "Dark"
    end
  end
end
```

The 2>/dev/null suppresses the "key not found" error that
defaults read emits when the user is in light mode (the key
is absent from defaults; presence-and-equal-to-Dark indicates
dark mode).

There's also a `dark_mode.rb` in `refactor/ruby/devel/`
(presumably an earlier iteration). Both saved at
`code-archive/refactor-modular/`.

## Design ideas that survive the pivot

- The `defaults read NSGlobalDomain AppleInterfaceStyle`
  approach (the standard macOS way to detect dark mode)
- The `2>/dev/null` suppression of the "key not found" error
- The `enabled?` predicate returning a Boolean

## Design ideas that don't survive

- The `MacOSInterface::DarkMode` namespace. W3 collapses to
  `Babble::Formatter` or a similar single helper:
  ```ruby
  module Babble
    module Formatter
      def self.dark_mode_enabled?
        stdout, status = Open3.capture2(
          "defaults", "read", "NSGlobalDomain", "AppleInterfaceStyle"
        )
        status.success? && stdout.strip == "Dark"
      end
    end
  end
  ```
- The `2>/dev/null` shell-string approach. W3 uses
  `Open3.capture2` with separate stderr capture (the
  `_, stderr` is just discarded), avoiding shell-string
  composition.
- Some apps now respect "Auto" appearance (light during day,
  dark at night) — `defaults read` returns `"Dark"` only when
  literally dark. This is fine for babble's current usage but
  worth a note.

## Bugs / blockers found

None. This is one of the cleaner refactor/modular files.

## What feeds W3

- The `defaults read` invocation
- The `enabled?` predicate as the public API
- Inlining as a small helper (no separate sub-module
  necessary)

<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Waiter

## Purpose

The interactive UI module. Pauses execution at phase
boundaries with "Press space to continue, or Ctrl-C to exit"
prompts. Lets the maintainer survey what's about to happen
(e.g., the list of outdated packages just printed) before
committing to the next action.

This is babble's primary UX mechanism for "I don't want this
to be fully automated; I want checkpoints."

## Refactor/modular implementation

`refactor/ruby/ui/waiter.rb` (~134 lines). Preserved at
`code-archive/refactor-modular/ui/waiter.rb`. Multiple
versions in `refactor/ruby/devel/integrated/`:
`waiter-v8.rb`, `waiter-v9.rb`.

Core method:

```ruby
module Waiter
  def self.waiter(action_name)
    print "--> Run command: Press Space bar to continue, or Ctrl-C to exit."
    # ... read raw character input from terminal
    # If space, return; if Ctrl-C, exit
    puts "\nContinuing..."
  end
end
```

The implementation needs to handle terminal input correctly:
disable line buffering and echo via `stty -icanon -echo`,
read a single character, restore terminal state. The devel/
versions explore different approaches (using `IO.console`
vs `STDIN.raw`, vs shelling out to stty).

## Design ideas that survive the pivot

- The `--> Run command: Press Space bar to continue, or
  Ctrl-C to exit.` prompt phrasing (visually distinct from
  brew/mas output; signals user input is expected)
- The space-to-continue / Ctrl-C-to-exit binary response
- The `Continuing...` confirmation echo
- Phase-boundary placement: between every major action
  that the user might want to abort

## Design ideas that don't survive

- The bare `Module.method` invocation style. W3 makes this a
  proper class with public API:
  ```ruby
  Babble::Waiter.confirm("Next: list outdated packages")
  ```
- Multiple competing terminal-handling implementations.
  Pick one, document it. `IO.console` is the cleanest
  Ruby-stdlib approach.
- The bare `print` without using the formatter. W3 emits
  via `oh1 "⨀ ..."` for the prompt prefix, then calls into
  the raw-input handling for the actual character read.

## Bugs / blockers found

The terminal-handling approach in refactor/modular (whichever
of the devel/ variants ended up in lib/) wasn't tested
against all the maintainer's terminals (e.g., iTerm2, Apple
Terminal, possibly remote SSH sessions). W3 should test
against at least iTerm2 and Apple Terminal explicitly.

## What feeds W3

- The phase-boundary prompt mechanism as core UX
- The space-or-Ctrl-C binary
- The prompt phrasing convention (`Next: <action>`,
  per the message-wording fix in
  `../03-known-bugs-and-rough-edges.md`)
- Integration with `Babble::Formatter` (use `ohai` for the
  prompt; `puts` for the `Continuing...` echo; raw STDIN
  for the character read)
- A `--no-confirm` or `--yes` flag for non-interactive
  invocations (CI, scripts) that bypass the waiter prompts

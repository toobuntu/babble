<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Retry

## Purpose

Retry-on-failure helper for transient errors during
`brew upgrade` (and possibly `brew update`). Wraps an
operation in a loop with bounded attempts and a hook for
cleanup between attempts.

The original ksh `bbl` had this; refactor/modular's Ruby port
did not bring it forward. The W3 external-command rewrite
restores it.

## Original ksh implementation

The ksh `bbl` had a `repeat_command` function used to wrap
`brew upgrade` invocations. Up to 10 attempts; between
attempts, clear `~/Library/Caches/Homebrew/bootsnap`. Added
in response to transient bootsnap-cache corruption discussed
in [Homebrew/brew discussion #5226](https://github.com/orgs/Homebrew/discussions/5226).

Approximate ksh shape (preserved in v0.5.x branches):

```ksh
function repeat_command {
  typeset -i max=${1:-10}
  shift
  typeset -i attempt=0
  while (( attempt < max )); do
    "$@" && return 0
    attempt=$((attempt + 1))
    rm -rf "${HOME}/Library/Caches/Homebrew/bootsnap"
  done
  return 1
}

repeat_command 10 brew upgrade --greedy-auto-updates --fetch-HEAD --display-times
```

## Refactor/modular state

Not ported. There's a comment in `brew_upgrade.rb`
acknowledging the regression but no implementation.

## Design ideas that survive the pivot

- Bounded retries (10 max)
- Cleanup hook between attempts (clear bootsnap cache)
- Wrap exactly the operation that fails, not the whole pipeline

## Design ideas that don't survive

- Plain ksh function shape. W3 implements as a proper Ruby
  module:

  ```ruby
  module Babble
    module Retry
      class << self
        sig {
          params(
            max: Integer,
            on_fail: T.proc.params(attempt: Integer).void,
            block: T.proc.returns(T::Boolean),
          ).returns(T::Boolean)
        }
        def with_retry(max: 10, on_fail: ->(_n) {}, &block)
          attempts = 0
          loop do
            return true if block.call
            attempts += 1
            return false if attempts >= max
            on_fail.call(attempts)
          end
        end
      end
    end
  end
  ```

  Used in BrewUpgrade as:

  ```ruby
  result = Babble::Retry.with_retry(
    max: 10,
    on_fail: ->(_n) { clear_bootsnap_cache },
  ) do
    Homebrew::Cmd::Upgrade.new([...]).run
    true  # or check result
  end
  ```

## Bugs / blockers found

None — never ported, so no bugs to inherit. The original ksh
version worked.

## What feeds W3

- The `Babble::Retry` module with a single `with_retry`
  method
- The default cleanup hook for bootsnap cache
- Integration into `BrewUpgrade#upgrade_packages`
- Possibly extension to `BrewUpdate#update_brew` if the
  same transient-failure pattern affects `brew update`
- Tests for the retry behavior (succeeds first try, succeeds
  on retry, fails all attempts, calls on_fail correctly)

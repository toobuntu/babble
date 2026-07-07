---
# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

number: 2
title: "Output formatting: ⨀ prefix on Homebrew helpers"
status: accepted
date: 2026-07-03
decision-makers:
  - toobuntu
---

# Output formatting: ⨀ prefix on Homebrew helpers

## Context and Problem Statement

`brew babble` interleaves its own status output with output from the
tools it drives (`brew update`, `brew upgrade`, `mas`,
`softwareupdate`). Homebrew's own lines look like `==> Updated 1 tap`.
Babble's lines need to be recognizably babble's at a glance, without
inventing a parallel output system.

## Decision Drivers

* Homebrew's `oh1`/`ohai`/`opoo`/`ofail` already provide the visual
  hierarchy (headline size/position conventions) — do not reinvent it.
* Severity colors should come for free: `opoo` is yellow, `ofail` is
  red.
* `HOMEBREW_NO_COLOR` and TTY detection must keep working; babble's
  output must stay distinguishable even with color off.
* One maintainer: custom helpers are permanent carrying cost.

## Considered Options

* **Option 1 — custom helpers with custom color.** `babble_oh1` /
  `babble_ohai` etc., mirroring Homebrew's functions but emitting in
  cyan. Distinguishes by *color*.
* **Option 2 — Homebrew helpers; prefix the message with `⨀`.**
  `oh1 "⨀ Babble message"` produces `==> ⨀ Babble message`.
  Distinguishes by *symbol*.
* **refactor/modular's partial approach** — raw ANSI codes for a cyan
  `⨀=>` in some `puts` calls, plain `==>` and bareword text elsewhere.

## Decision Outcome

Chosen option: **Option 2**, because the `⨀` glyph identifies
babble's output regardless of severity or color support, the size and
position hierarchy stays Homebrew's, severity colors are inherited
rather than reimplemented, and `HOMEBREW_NO_COLOR`/TTY handling flows
through the stock helpers untouched.

```ruby
oh1   "⨀ Babble: Phase 1 — Update Homebrew"
ohai  "⨀ Quitting Stats..."
opoo  "⨀ Skipping iterm2 (running terminal)"
ofail "⨀ Failed to launch Stats after upgrade"
```

The prefix lives in exactly one place: `Babble::Formatter`
(`cmd/babble/formatter.rb`), whose `oh1`/`ohai`/`opoo`/`ofail`
wrappers prepend `⨀ ` and delegate to `Utils::Output::Mixin`. Call
sites use `Babble::Formatter` and never hardcode the glyph.
refactor/modular's cyan ANSI codes are not preserved; its mixed
cyan-`⨀=>` / plain `==>` / bareword output is cleaned up to this
uniform pattern.

### Consequences

* Good, because `==> ⨀ Babble: Phase 1` next to `==> Updated 1 tap`
  is unambiguous even without color contrast.
* Good, because babble inherits severity colors, TTY detection, and
  `HOMEBREW_NO_COLOR` from Homebrew's helpers with zero custom code.
* Good, because the convention is testable in one unit
  (`test/cmd/babble/formatter_spec.rb`).
* Bad, because babble's headlines render in Homebrew's colors, not a
  babble-specific one — the glyph alone carries the identity.
* Neutral, because `⨀` (U+2A00) requires a font with decent Unicode
  coverage; every terminal the maintainer targets renders it.

## More Information

Source analysis:
[`../migration-investigation/01-decisions.md`](../migration-investigation/01-decisions.md)
§ "Output formatting: ⨀ prefix on Homebrew helpers (option 2)".
Locked in the master plan § W3; implemented by Block B
(`cmd/babble/formatter.rb`).

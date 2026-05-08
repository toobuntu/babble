<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# TerminalDetector

## Purpose

Detects which terminal application babble is running inside,
so that terminal CAN be excluded from the quit/reopen lifecycle.
Quitting babble's host terminal mid-run terminates babble itself
— a self-inflicted denial-of-service.

This module is **design-only** — there is no implementation in
refactor/modular. PR #3 attempted to address this concern but
its approach was fundamentally broken (the `brew upgrade
--except` flag doesn't exist; the rebase-onto-PR-#1 was never
persisted to the remote). The W3 implementation starts fresh
from this design.

## Refactor/modular implementation

None. The maintainer recognized terminal-exclusion as a needed
feature but never implemented it before pivoting to the
external-command rewrite. The omission is documented in
`refactor/ruby/TODO`.

## PR #3 attempt

`origin/copilot/fix-terminal-upgrade-issue` was Copilot
(Sonnet 4.6)'s attempt at this. The approach:

1. Detect the running terminal via env variables
   (`TERM_PROGRAM`, `LC_TERMINAL`)
2. Map terminal name to cask token
3. Pass the cask token to `brew upgrade` with a hypothetical
   `--except` flag to skip it

Bugs (per `../reviews/pr3-review.md`):
- `brew upgrade --except` does not exist; the entire
  command-line construction is invalid
- The rebase-onto-PR-#1 the description claimed was never
  persisted to the remote (only the original commit against
  main exists)
- Allowlist of terminal casks confuses editors
  (VSCode, MacVim, Emacs) with terminals — they're not
  terminals; they're editors that may run shell commands

Discarded entirely. The "what to keep" section of the PR-3
review captures the survival design intent.

## Surviving design (for W3)

**Detection strategy** (env-var-first, process-tree fallback):

1. **`TERM_PROGRAM` env var** — set by most modern macOS
   terminals (Apple Terminal, iTerm2, Tabby, Alacritty,
   Kitty, Wezterm, etc.). Maps to a known terminal name.
2. **`LC_TERMINAL` env var** — set by some terminals (iTerm2)
   for finer-grained identification.
3. **`__CFBundleIdentifier` env var** — set by macOS when an
   app is launched via the LaunchServices framework. Direct
   bundle ID match.
4. **Process tree walk fallback** — if env vars are absent
   (e.g., the user `nohup`'d babble out of a non-terminal
   process), walk up the process tree via `ps -o ppid=,comm=`
   until reaching launchd or a known terminal binary.

**Terminal-cask mapping** (allowlist, EXPLICITLY NOT inclusive
of editors):

```yaml
# Examples; full list in the W3 implementation
terminals:
  - name: "Apple_Terminal"
    bundle_id: "com.apple.Terminal"
    casks: []  # ships with macOS, no cask
  - name: "iTerm.app"
    bundle_id: "com.googlecode.iterm2"
    casks: ["iterm2"]
  - name: "tabby.app"
    bundle_id: "org.tabby"
    casks: ["tabby"]
  - name: "alacritty"
    bundle_id: "org.alacritty"
    casks: ["alacritty"]
  - name: "Kitty"
    bundle_id: "net.kovidgoyal.kitty"
    casks: ["kitty"]
  - name: "WezTerm"
    bundle_id: "com.github.wez.wezterm"
    casks: ["wezterm"]
  - name: "Ghostty"
    bundle_id: "com.mitchellh.ghostty"
    casks: ["ghostty"]
```

NOT in this list: VSCode, Cursor, MacVim, Emacs, IntelliJ — these
are editors that *may* spawn shell processes but don't host
babble as a terminal program. They get treated like any other
app (subject to normal quit/reopen).

**Exclusion mechanism**: when constructing
`casks_to_quit_and_reopen` in `BrewUpgrade`, exclude any cask
in the detected terminal's `casks` list. Don't quit; don't
reopen. The terminal's upgrade gets deferred — it's still in
the `brew upgrade` set (will get the new version installed),
but the running process keeps running with the old binary.
The user notices on next launch.

**Edge cases to handle**:
- User running babble inside `tmux` or `screen` — detect via
  `$TMUX` or `$STY`, walk up to find the actual terminal
- User running via SSH — `$SSH_TTY` set, no GUI terminal,
  no quit needed; entire mechanism is N/A
- User running via macOS's open-with-Terminal — same as direct
  Terminal launch
- User SSH'd into another machine and then ran babble —
  `TERM_PROGRAM` will reflect the local terminal but the
  upgrade is on the remote; mismatch, but not babble's problem
  (the user took explicit action)

## Design ideas that survive the pivot

All of the surviving design above. None of PR #3's actual code.

## Bugs / blockers found

None — design phase only.

## What feeds W3

- A new `Babble::TerminalDetector` module (in `lib/babble/`
  for standalone, `cmd/babble/` for external-command shape)
- The detection strategy with env-var-first / process-tree
  fallback
- The terminal-cask allowlist (extensible via config; ships
  with sensible defaults)
- Integration into `BrewUpgrade`'s
  `casks_to_quit_and_reopen` filtering
- Specs for each detection path (env-var present, env-var
  absent + ps walk, ssh case, tmux case)
- Documentation in the README explaining the exclusion
  behavior so users understand why their terminal didn't
  quit/reopen

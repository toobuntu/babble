<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# PR #3 review — Fix Babble upgrade issue with running terminal app

This PR is being closed without merging. The terminal-exclusion feature it
attempts will be reimplemented from scratch in the new Ruby code base; the
section "What to keep" at the bottom captures the few ideas worth carrying
forward.

## Why this branch is being discarded

### Branch state mismatch

The PR description says the implementation is stacked on top of PR #1 ("I
have updated the implementation to be based on top of PR#1"). The actual
on-disk state of `copilot/fix-terminal-upgrade-issue` is a ksh-only patch
to the original `bbl` script. There is no Ruby code on this branch — no
`bin/babble`, no `lib/babble/`, nothing from PR #1.

The Copilot conversation log shows two consecutive errors mid-session:

> Copilot has encountered an error. See logs for additional details.
> Changes were pushed to Copilot's branch while it was working, and Copilot
> was unable to merge its changes with the contents of the remote branch.

Whatever the branch description claims, the rebased work doesn't appear to
have made it to the remote. What we have instead is a stand-alone ksh
patch with a fatal bug, described next.

### `brew upgrade` has no `--except` flag — the patch can't run

The patch's central change is to construct the upgrade command with an
exclusion:

```sh
typeset command_to_repeat
if test -n "$running_terminal_token"; then
  command_to_repeat="brew upgrade --greedy-auto-updates --fetch-HEAD --no-quarantine --display-times --except=$running_terminal_token"
else
  command_to_repeat="brew upgrade --greedy-auto-updates --fetch-HEAD --no-quarantine --display-times"
fi
```

`brew upgrade` does not accept a `--except` flag. It accepts a list of
explicit packages to upgrade (in which case only those are upgraded), or
no arguments (in which case all outdated packages are upgraded). Homebrew
documents `brew pin <name>` as the supported exclusion mechanism for
formulae, and there is no equivalent for casks. So the moment a running
terminal is detected, the upgrade step fails with an "unknown option"
error from Homebrew; on every other run, the conditional happens to skip
this branch and the original behavior is preserved.

This means the feature has a 100% failure rate when the feature actually
fires. The patch can never have been tested with `TERM_PROGRAM` set to one
of the recognized values.

### The process-tree fallback never resolves a terminal

The fallback to `TERM_PROGRAM` walks the parent chain looking for a
process whose path contains `.app/`:

```sh
proc_path=$(ps -p "$parent_pid" -o comm= 2>/dev/null)
if test -n "$proc_path" && echo "$proc_path" | grep -q '\.app/'; then
```

On macOS, `ps -o comm=` returns the command's basename — for example
`iTerm2`, not `/Applications/iTerm.app/Contents/MacOS/iTerm2`. So the
`grep -q '\.app/'` test never matches, and the fallback never resolves a
bundle ID. The feature only works if `TERM_PROGRAM` is set and one of
the entries in the bundle-to-token map matches. Since the
`TERM_PROGRAM`-only path also can't actually run (the `--except` bug
above), the fallback being broken is academic — but worth noting for the
re-implementation.

(For the record, the macOS-correct way to get the parent's executable
path is `ps -p $pid -o command=` — note `command`, not `comm` — though it
truncates by default. The reliable approach is the libproc-based
`proc_pidpath()`, which Ruby can call via `RubyVM::Util` or shell-out via
`lsof -p $pid -F n` and string-extract the executable. Or more simply,
`ps -p $pid -o args=` for the full command line.)

### The bundle-ID-to-token map conflates terminals with editors

```sh
typeset -A terminal_bundle_to_token=(
  [com.apple.Terminal]=terminal
  [com.googlecode.iterm2]=iterm2
  [io.alacritty]=alacritty
  [net.kovidgoyal.kitty]=kitty
  [com.github.wez.wezterm]=wezterm
  [co.zeit.hyper]=hyper
  [org.gnu.Emacs]=emacs
  [org.vim.MacVim]=macvim
  [com.microsoft.VSCode]=visual-studio-code
  [com.vscodium]=vscodium
)
```

The intent is to detect terminals. The implementation includes editors —
Emacs, MacVim, VSCode, VSCodium — that *contain* terminals. The
PR-description claim "VSCode integrated terminal" is the only scenario
where these matter, and even then the right user expectation is muddled:
if babble runs inside VSCode's integrated terminal and detects VSCode as
"the terminal," it skips the VSCode upgrade — which is fine for
preserving the running session, but means VSCode itself never gets
upgraded by babble. The user expected to upgrade VSCode; babble silently
declines.

The list also contains `com.apple.Terminal → terminal`, where `terminal`
is not an actual Homebrew cask token (Apple's Terminal isn't in
Homebrew). Mapping it to a non-existent cask is a no-op when paired with
a working `--except`, but it's also non-information that confuses the
intent of the table. PR #3's own description says "Terminal.app excluded
as it's not part of the Homebrew ecosystem" — and yet here it is in the
map.

### Process-tree walk: 20-iteration cap with no rationale

```sh
typeset -i level=0
while test "$level" -lt 20 && test "$current_pid" -gt 1; do
  ...
  level=$((level + 1))
done
```

20 is arbitrary. macOS process trees in practice are 5-8 deep from a
shell to launchd. Either drop the cap or document why 20 (probably
"defensive against a runaway"). Minor.

### `set -x` retained around the `repeat_command` invocation

The patch keeps the `set -x` ksh tracing wrapping `repeat_command`. Once
the `--except` flag fails, the tracing output makes the failure mode
visually overwhelming: every shell expansion in the wrapper is echoed
before the actual error is surfaced. This is a maintainability issue more
than a correctness issue, but it compounds the diagnostic burden.

---

## What to keep

The intent is sound and the README has carried this TODO since v0.5.0.
For the re-implementation in the Ruby branch, take these from PR #3:

1. **Two-tier detection**, env-var first. The `TERM_PROGRAM` →
   `bundle_id` mapping is a perfectly valid fast path for the common
   terminals (iTerm2, Alacritty, WezTerm, Hyper, Apple Terminal). Augment
   with `LC_TERMINAL` (set by some terminals like iTerm2) and
   `__CFBundleIdentifier` (sometimes set by Apple frameworks) before
   walking the process tree.

2. **Process-tree fallback for the unusual cases.** Re-implement using
   one of:
   - `lsof -p $$ -Fn` and grep for `.app/Contents/MacOS/` paths,
     walking up `ps -o ppid= -p $pid` until either we hit launchd or
     find a `.app` ancestor.
   - libproc via Ruby FFI (`Fiddle.dlopen("/usr/lib/libSystem.B.dylib")`
     and `proc_pidpath`), which is the macOS-native way.
   - `osascript -e 'path to frontmost application as POSIX path'` as a
     last resort, with the caveat that "frontmost" is not always the
     terminal hosting babble (think: babble running over SSH, or in
     `tmux` where focus tracking is murky). This last option is more of
     an "only if everything else fails" probe.

3. **Restrict to terminal casks.** Use a small allowlist of cask tokens
   that are *terminals* — `iterm2`, `alacritty`, `kitty`, `wezterm`,
   `hyper`, `warp`, `tabby`, etc. — and not editors that happen to host
   terminals. If the detected app isn't on the allowlist, log "running
   inside <app_name>; not a terminal cask, no exclusion needed" and
   move on. This avoids the editor-conflation problem.

4. **Implement exclusion via explicit upgrade list, not `--except`.**
   The right pattern in Ruby:

   ```ruby
   # Compute the outdated cask tokens
   outdated = outdated_cask_tokens   # array of strings

   # Filter out the running terminal, if any
   terminal_token = TerminalDetector.running_terminal_cask_token
   if terminal_token && outdated.include?(terminal_token)
     warn "Skipping #{terminal_token}: running as the parent terminal of babble. " \
          "Re-run babble from a different terminal to upgrade it."
     outdated -= [terminal_token]
   end

   # Upgrade only the surviving casks
   if outdated.any?
     system(brew_file, "upgrade", "--cask", "--greedy-auto-updates",
            "--fetch-HEAD", "--display-times", *outdated)
   end
   ```

   For formulae, no exclusion is needed (terminals are casks), so a
   plain `brew upgrade --formula` covers the rest.

5. **User-visible notification.** A clear, single-line message on stderr
   when the exclusion fires — modeled on the message above. Not buried
   in `set -x` tracing; not styled with multiple ANSI escape codes
   stacked. One line, plain, with a hint about how to upgrade it.

6. **No reliance on `TERM_PROGRAM` for editors.** If the user is running
   babble in VSCode's integrated terminal and VSCode is outdated, that's
   for `brew upgrade visual-studio-code` to handle separately. Babble
   should detect the integrated terminal as "VSCode" and inform the user,
   but should not exclude VSCode from upgrade — VSCode is not the
   terminal. (Alternative phrasing for the spec: babble excludes only
   apps that *are themselves the terminal*. An editor with a terminal
   tab is not the terminal.)

This functionality belongs in a `lib/babble/terminal_detector.rb` module
with `~10` lines of public API and a thorough RSpec covering each
detection path. It should be a separate PR after the PR #1 cleanup
lands.

---

## Disposition

Close without merging. Capture the disposition in a brief comment on the
PR (template below), and leave the branch in place as a reference for the
re-implementation. After the new `terminal_detector.rb` lands, the issue
referenced in the PR (#2) will be closed by that PR.

> Closing this in favor of a clean re-implementation on the post-#1 Ruby
> branch. Implementation here had a fatal bug (`brew upgrade --except`
> doesn't exist) and the rebase onto PR #1 the description claims was
> never persisted to remote. The terminal-detection idea is sound and
> will be redone in `lib/babble/terminal_detector.rb` once the Ruby
> migration cleanup is in place. Tracking continues at #2.

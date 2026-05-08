<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Rejected directions

This file documents approaches that were considered and
discarded during the year+ Ruby port and the subsequent
external-command pivot. Each entry: rationale for considering,
rationale for rejecting.

The point of preserving rejection rationales: when a future
implementation hits the same fork in the road, the prior
analysis is here. Saves re-deriving from scratch.

## Standalone library with project Gemfile

**Considered.** The original Ruby port plan (refactor/modular)
shipped a `Gemfile`, project-local `.rubocop.yml`, project
Sorbet config, project RSpec setup. PR #1 followed this
template. Rationale: independence from Homebrew's vendored
Ruby; modern Ruby toolchain; ability to use any gem.

**Rejected because** as an external command, babble runs
inside Homebrew's Ruby process with Homebrew's vendored gems.
The standalone shape introduces unnecessary
toolchain-bootstrapping work — every consumer needs to install
the Gemfile dependencies. The external command shape eliminates
that friction entirely. Trade-off: babble can use only the gems
Homebrew vendors. Acceptable; babble's actual gem needs are
narrow (YAML parsing, Open3, JSON — all stdlib).

## `brew bundle` as upgrade orchestrator

**Considered.** `brew bundle` reads a `Brewfile` and applies it
to the system: install missing formulae and casks, upgrade
existing ones, optionally remove unlisted ones. It also
supports mas apps and vscode extensions. On the surface, this
overlaps with babble's purpose.

**Rejected because** `brew bundle` is declarative-state-only.
It will happily upgrade VSCode while VSCode is running, leaving
the user staring at a dialog telling them to restart. It has
no quit/reopen lifecycle, no `unsafe_to_quit` confirmation
dialog, no per-app restart logic. The visual feedback during
upgrades is also terse — `brew bundle install` prints brief
status; babble surfaces verbose upgrade output and per-section
"Continuing..." prompts. Different workflows.

There may be partial reuse: if babble eventually wants to
discover what apps the user has installed for the source-of-truth
problem, `brew info --installed --json=v2` (or, in external-command
form, `Formula.installed` / `Cask::Caskroom.casks`) gives clean
machine-readable data. `brew bundle dump` does too, but the
direct API path is preferable for an external command.

## `brew typecheck` for babble's library code

**Considered.** Use `brew typecheck` to run Sorbet on babble's
Ruby files. Homebrew already has the Sorbet config and rbi
files; babble inherits them.

**Rejected because** `brew typecheck` is private API limited to
the `Homebrew/brew` repo. It hardcodes paths under
`HOMEBREW_LIBRARY_PATH/sorbet/`. Third-party Ruby (even
external commands) can't invoke it. As an external command,
babble's typecheck happens at CI via the same path cask-tools
uses: link the `cmd/babble.rb` file into
`$(brew --repo)/Library/Homebrew/cmd/` during CI, then
`brew tests --only=cmd/babble` exercises Sorbet implicitly.

## Project-local RuboCop with `homebrew-rubocop` config

**Considered.** Use `bundle exec rubocop` with Homebrew's
rubocop gem as a config inheritance point. Same lint rules,
project-local invocation.

**Rejected because** `brew style <files>` does the same thing
without the Bundler ceremony. Cask-tools' CI runs
`brew style --changed`; babble inherits this pattern. No
project Gemfile, no `bundle exec` prefix, no project rubocop
config. Cleaner.

## Pre-built Swift quit_alert binaries

**Considered (and used in refactor/modular).** Pre-compile the
Swift dialog as architecture-specific binaries
(`quit_alert_arm64`, `quit_alert_x86_64`), commit them to the
repo under `swift/build/dist/`, ship to users via
`git clone`.

**Rejected because** the maintainer has no Apple Developer
certificate. Without one, the binaries can be ad-hoc-signed
but not Developer-ID-signed. On Apple Silicon, Gatekeeper
rejects ad-hoc-signed binaries that have the
`com.apple.quarantine` extended attribute (which all
downloaded files have). Result: Gatekeeper blocks the
binary on first launch; the user gets a "cannot be opened"
dialog.

For the maintainer's local development, this didn't matter
(local files don't carry quarantine; ad-hoc-signed local
binaries run fine). For distribution, it does.

The decision: auto-compile on first run via `xcrun swiftc`,
caching the compiled binary in `$XDG_CACHE_HOME/babble/swift/`
(or similar). Trade-off: requires xcode-command-line-tools at
runtime (already a dependency for many Homebrew formulae);
first run is slower; no notarization concerns. Detailed in
`adrs/0001-swift-quit-alert-build-strategy.md`.

## Custom formatter helpers (`Babble.oh1` etc.)

**Considered.** Define `babble_oh1`, `babble_ohai`, etc. —
helpers that mirror Homebrew's but emit in cyan instead of
magenta to distinguish babble's output from Homebrew's by
color.

**Briefly accepted then rejected.** The earlier design
recommended using `Formatter.headline(text, color: :cyan)`
to get cyan `==>` emission. Rolled back: the cyan distinction
requires custom helpers to maintain Homebrew's `oh1`/`ohai`
size-and-position hierarchy, adding maintenance burden for
a visual gain that the `⨀` symbol prefix already provides.

refactor/modular took a partial cyan approach with raw ANSI
codes, but only in select `puts` lines — the cyan didn't
propagate to `opoo` or `ofail`, leaving an inconsistent mix of
cyan-`⨀=>`, plain `==>` (Homebrew shell-out), and bareword.
The inconsistency is what we're cleaning up.

**Rejected because** the visual distinction is sufficient via
`⨀` prefix on Homebrew's existing helpers:
- `oh1 "⨀ Babble: Phase 1"`
- `ohai "⨀ Quitting Stats"`
- `opoo "⨀ Skipping iterm2"`
- `ofail "⨀ Failed to launch Stats"`

The `⨀` glyph is visually distinctive enough that color
doesn't add meaningful information. Severity colors (yellow
for `opoo`, red for `ofail`) come for free from Homebrew's
helpers. `HOMEBREW_NO_COLOR` and TTY detection are respected
through `oh1`/`ohai`/etc. without a custom code path.

Concrete impact: ~30 lines of helper code avoided; consistent
size/position hierarchy via Homebrew's helpers; consistent
severity color via Homebrew's helpers; respect for environment
color settings preserved.

## `brew bundle dump` for installed-app discovery

**Considered.** Use `brew bundle dump --casks --mas` to get
a machine-readable list of installed apps. Babble could read
the Brewfile and use it as the source of truth for what's
upgradable.

**Rejected because** as an external command, babble has direct
access to `Formula.installed`, `Cask::Caskroom.casks`, and
mas-related calls. No shell-out to `brew bundle`, no parsing of
its output, no temporary file. The direct API path is faster
and more idiomatic.

`brew bundle dump` may still have a role for users who maintain
a Brewfile-as-source-of-truth and want babble to consult it.
Tracked as a low-priority follow-up: read `~/Brewfile` (or
`$BREWFILE`) if present and use it as one input to the
"what's installed" set, alongside the Homebrew installed-cask
list.

## Base64 encoding of bundle ID arrays

**Considered (and implemented on the `base64` branch).** In ksh,
arrays cannot be exported across subshell boundaries. The ksh
script needed to capture the list of running app bundle IDs
before quitting them, then restore the same list after upgrade
to know which apps to relaunch. The state had to survive
multiple subshell invocations.

The base64 approach: encode a NUL-separated list of bundle IDs
via `openssl base64 -A`, store in an exported variable,
decode after upgrade.

```ksh
# Capture running app bundle IDs and base64-encode for export
restart_req_export="$(/usr/bin/lsappinfo list | \
  /usr/bin/awk -F'"' '/bundleID/{print $2}' | \
  /usr/bin/sort -u | \
  /usr/bin/tr '\n' '\0' | \
  /usr/bin/openssl base64 -A)"
export restart_req_export

# ... brew upgrade happens ...

# Decode after upgrade
typeset -a restart_req
/usr/bin/openssl base64 -d -a -A <<< "$restart_req_export" | \
  tr "\0" "\n" | \
  while IFS="" read -r line; do
    restart_req+=("$line")
  done
```

**Rejected because** Apple's CFBundleIdentifier specification
restricts bundle IDs to alphanumeric characters, hyphens,
periods. Commas are explicitly disallowed. So any single ASCII
character disallowed in bundle IDs (comma, semicolon, colon,
slash, etc.) can serve as a delimiter without ambiguity. The
base64-then-NUL-decode-then-array approach is overkill.

Switched to comma-separated values:

```ksh
# Capture
restart_req_export="$(/usr/bin/lsappinfo list | \
  /usr/bin/awk -F'"' '/bundleID/{print $2}' | \
  /usr/bin/sort -u | \
  /usr/bin/tr '\n' ',')"
export restart_req_export

# Decode
restart_req=( $(printf "%s" "$restart_req_export" | /usr/bin/tr "," "\n") )
```

Simpler; readable; no openssl dependency.

The comma approach itself was then rejected at the Ruby port,
which can pass arrays directly without the export-encode-decode
dance. Refactor/modular's `set_running_apps` returns
`Array[String]` straight from the lsappinfo parser.

The base64 branch's `NOTES.txt` preserves the rationale chain
in detail. Worth reading for the macOS-shell-trivia: how to
print NUL via printf, why NUL can't be in a shell variable but
can be in a pipe/file, the comparison between
`/usr/bin/openssl base64`, `/usr/bin/base64`, and
`/usr/bin/uuencode -mr` for portability.

## NUL-terminated bundle ID strings

**Considered (briefly, before the base64 branch).** Use NUL
('\0') as the delimiter for bundle IDs, mirroring how
`find -print0 | xargs -0` and similar tools handle filenames
with whitespace.

**Rejected because** NUL cannot be stored in a shell variable
on macOS. The shell uses NUL as the variable terminator
internally. NUL can be used in pipes (between processes) and
in files, but not in environment variables. Since the
ksh script needed to export the list across subshell
boundaries, file-based or pipe-based NUL handling was a poor
fit. (Hence the base64 detour, then the comma resolution.)

## Homemade quarantine purger

**Considered (and implemented in refactor/modular and PR #1).**
Both versions had a `quarantine_purger.rb` that ran
`xattr -d com.apple.quarantine` on installed cask bundles.
Single-tier: just iterate over caskroom contents.

**Rejected because** cask-tools already ships
`brew purge-quarantine` with a sophisticated seven-tier bundle
discovery (Caskroom glob → Cask API → metadata JSON →
lsregister → pkgutil receipts → pkgutil BOM → mdfind). It
handles cases babble's homemade version would miss
(pkg-installed casks, casks no longer in any tap,
non-standard install locations, plugin packages). Delegating
to cask-tools eliminates duplicate maintenance burden.

The external-command babble simply calls
`Homebrew::Cask::PurgeQuarantine` (or whatever name survives
the W7 `BundleDiscovery` extraction) for the post-upgrade
quarantine purge. Tap dependency on cask-tools for users who
want this; opt-out for users who don't.

## Ksh as the implementation language

**Considered (and was the v0.5.x reality).** The original
babble (`bbl`) was ksh93. Stayed ksh through 2024. The
maintainer's general convention is ksh for system administration
scripts since macOS ships `/bin/ksh`.

**Rejected because** babble's use case isn't really sysadmin —
it's interactive orchestration of brew/mas/macOS upgrades. The
phase-by-phase logic (parse outdated → quit apps → run
upgrades → reopen apps → run softwareupdate → cleanup) is
naturally object-oriented. Ksh has no good way to express this
cleanly at scale; the v0.5.x bbl was 700+ lines of one big
flat script, hard to test, hard to extend. Ruby modular code is
cleaner.

The W3 external command continues this trajectory — Ruby, but
no longer standalone (inside Homebrew's process). Ksh stays
the right choice for *other* scripts: blackoutd's
sandbox-enter scripts, repo-foundation's annotate.sh and
related utilities. Just not babble.

## Tools that operate on the user's behalf without confirmation

**Considered (briefly, in early v0.x of bbl).** Skip the "Press
space to continue" prompts; just run the upgrade end-to-end.
Faster.

**Rejected because** brew upgrade can take significant time
(dozens of casks; large downloads; per-app post-install
hooks). Without staging prompts, an interruption at the wrong
moment leaves the user unsure where the upgrade was. The
"Press space to continue" boundaries serve as natural
checkpoints: between `brew update` and `brew outdated`,
between `brew outdated` and the per-cask quit phase, between
the upgrade and the reopen phase, etc. The maintainer can
ctrl-C at any boundary without leaving the system in a
half-upgraded state.

The text wording around these prompts has rough edges (see
`03-known-bugs-and-rough-edges.md` § "Confirmation prompt
phrasing"); the prompt mechanism itself stays.

## A separate mas-token-generator subcommand

**Considered (and implemented in refactor/modular as
`refactor/ruby/utils/mas_token_generator.rb`).** A standalone
script that generates the mas-store-style token for a given
app ID. Useful for populating the apps.yml.

**Rejected because** mas v7 introduced `mas info <app_id> --json`
which provides everything the generator was computing,
authoritatively. The token-generator script becomes a
historical artifact — its inputs/outputs are now subsumed by
mas itself. The W3 external command can drop it; the apps.yml
maintenance flow becomes "look up the bundle ID from
`mas info <app_id> --json | jq -r .bundleID`."

This particular utility is worth preserving in `code-archive/`
as an example of the kind of tooling the v0.5.x development
required. Not because the W3 external command needs it.

<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Known bugs and rough edges

This file catalogs issues identified during refactor/modular's
year of daily use, plus issues found during the planning
session. The W3 external-command rewrite addresses each as
appropriate. None of these are addressed in pre-pivot code (per
the W2 preservation-only scope); they are documentation for the
rewrite to consume.

## Confirmation prompt phrasing redundancy

The current refactor/modular output has redundant "doing X"
messages that fire BEFORE the user has confirmed the action.
Sample output (preserved from `refactor/ruby/devel/wip/brew_upgrade-fixme.txt`):

```
Listing installed packages which are outdated...
Would run `brew outdated`
--> Run command: Press Space bar to continue, or Ctrl-C to exit.
Continuing...
Outdated packages:
boost (1.87.0_1) < 1.88.0
stats (2.11.39) != 2.11.40
Proceeding with upgrades...
The following casks are scheduled for upgrade and will require quitting/reopening:
  stats
Quitting eu.exelban.Stats...
Successfully quit application: eu.exelban.Stats
Upgrading all outdated packages...

Upgrading outdated packages...
Would run `brew upgrade`
--> Run command: Press Space bar to continue, or Ctrl-C to exit.
Continuing...
==> Upgrading 2 outdated packages:
...
Reopening eu.exelban.Stats...
Upgrade process complete.
Reopened necessary applications after upgrade.
```

Two issues:

**Issue 1 — Pre-confirmation "doing X" lines.** The lines

- `Listing installed packages which are outdated...`
- `Upgrading all outdated packages...`
- `Upgrading outdated packages...`

are printed BEFORE the user presses space. The phrasing is
present-progressive ("doing X now") but the action hasn't
happened yet — `brew outdated` runs only after space is
pressed. Misleads the reader.

**Issue 2 — Doubled "Upgrading outdated packages" line.** Two
back-to-back lines say almost the same thing:

```
Upgrading all outdated packages...

Upgrading outdated packages...
```

Looks like a copy-paste artifact.

**Fix (W3):** Change pre-confirmation lines to "Next:" or
"Preparing to..." or "About to run...":

```
Next: list outdated packages
--> Run command: Press Space bar to continue, or Ctrl-C to exit.
Continuing...
[brew outdated runs here]
Outdated packages:
boost (1.87.0_1) < 1.88.0
stats (2.11.39) != 2.11.40

Next: quit running apps tied to outdated casks
[lists the casks/bundle IDs]
[per-cask quit JXA invocation]

Next: upgrade outdated packages
--> Run command: Press Space bar to continue, or Ctrl-C to exit.
Continuing...
[brew upgrade runs here]

Next: reopen apps that were quit
[per-bundle reopen via BundleLauncher]
```

Drop the `Upgrading all outdated packages...` line entirely
(redundant with the upgrade phase header); use single
`Next: upgrade outdated packages` heading.

## Reversed completion messages

The end-of-run output:

```
Reopening eu.exelban.Stats...
Upgrade process complete.
Reopened necessary applications after upgrade.
```

`Upgrade process complete.` reads as a final summary — the
process is done. Then `Reopened necessary applications` reads
as a step that happened *after* the summary line. They're
inverted.

**Fix (W3):** Switch order so the summary actually comes last:

```
Reopening eu.exelban.Stats...
Reopened necessary applications after upgrade.
Upgrade process complete.
```

If the summary line should also distinguish "fully complete"
from "partially complete with errors", that's a separate
formatting decision; recommend showing the count of upgraded
packages and any failures:

```
Upgrade process complete: 2 packages upgraded, 1 reopened, no errors.
```

## brew_update fixme: descriptions duplicated by Homebrew

The babble `BrewUpdate#update_brew` method captures the list of
new formulae and casks from `brew update` output, then runs
`brew desc <token>` on each to display descriptions. This was
reasonable historically — `brew update` printed names only.

Homebrew/brew PR #20167 ("cmd/update-report: display descriptions
for new formulae and casks") changed that. As of recent
Homebrew versions, the update report includes descriptions
inline:

```
==> New Formulae
cutadapt: Removes adapter sequences from sequencing reads
freesasa: Solvent Accessible Surface Area calculations
lavinmq: Message broker implementing the AMQP 0-9-1 and MQTT protocols
==> New Casks
eez-studio: Visual tool for GUI development and T&M automation
open-webui: Desktop application for Open WebUI
```

The babble code now duplicates the description.

### Upstream's actual emission rules (from `cmd/update-report.rb`)

Reading the current upstream `update-report.rb` source
(specifically `ReporterHub#dump_new_formula_report` and
`#dump_new_cask_report`), the emission rules are:

1. **Section gated by `HOMEBREW_NO_UPDATE_REPORT_NEW`**.
   If set, neither names nor descriptions appear.
2. **Per-formula description emission**:
   - If `HOMEBREW_NO_INSTALL_FROM_API=1`: descriptions shown
     only if the new formulae list size is ≤ 100 items
     (size check is for performance — loading 100+ formula
     objects via `Formula[name]` is expensive)
   - Otherwise: descriptions always shown (pulled from the
     JSON API which is always available)
3. **Same logic for casks** (gate on
   `HOMEBREW_NO_INSTALL_FROM_API` and the 100-item ceiling)
4. **Format on emit**: `puts "#{formula}: #{desc}"` —
   token, colon, space, desc
5. **Description SOURCE**: For the `HOMEBREW_NO_INSTALL_FROM_API`
   path, calls `Formula[formula].desc` for formulae
   (loads the formula file). For casks,
   `Cask::CaskLoader.load(cask).desc`. The `&.presence`
   chain returns `nil` if desc is empty/missing.
6. **Fonts and other no-desc casks**: there's no special
   casing in the `description` method itself. If a font cask
   has `desc nil` in its definition, the method returns
   `nil`, and the line just prints `cask_token` without
   `: desc`. So the parsing logic "look for `: desc` to
   determine whether to call `brew desc`" works correctly
   for fonts — they print as bare tokens.

### Fix (W3)

W3 detects upstream's already-printed descriptions by line
shape, eliminating the version-detection complexity:

```ruby
# Babble::BrewUpdate parser
in_new_formulae = false
in_new_casks = false
new_formulae = []  # array of {token:, has_desc:}
new_casks = []     # array of {token:, has_desc:}

stdout.each_line do |line|
  cleaned = strip_ansi_escape_sequences(line.strip)

  case cleaned
  when /^==>.*New Formulae/
    in_new_formulae = true; in_new_casks = false
  when /^==>.*New Casks/
    in_new_formulae = false; in_new_casks = true
  when /^==>/, /^You have/, /^Already up-to-date$/, /^The /
    in_new_formulae = false; in_new_casks = false
  else
    next if cleaned.empty?
    has_desc = cleaned.match?(/^\S+: \S/)
    token = has_desc ? cleaned.split(":", 2).first.strip : cleaned
    new_formulae << { token:, has_desc: } if in_new_formulae
    new_casks    << { token:, has_desc: } if in_new_casks
  end
end

# After parsing: re-emit descriptions for items missing them
return if ENV["HOMEBREW_NO_UPDATE_REPORT_NEW"]

unless new_formulae.empty?
  oh1 "⨀ Babble: descriptions of new formulae"
  new_formulae.each do |entry|
    next if entry[:has_desc]   # upstream already printed
    safe_system HOMEBREW_BREW_FILE, "desc", "--formula", entry[:token]
  end
end
# similarly for new_casks
```

Properties of this approach:
- **Detects descriptions by parsed line shape**, not by
  Homebrew version. Robust against future upstream changes.
- **Fonts are handled correctly**: `font-pragmatapro` has
  no desc → line is bare token → `has_desc=false` → babble
  invokes `brew desc --cask font-pragmatapro` → returns
  empty (per the cask's `desc nil`) → user sees just the
  token. Same end result, no special-casing.
- **Honors `HOMEBREW_NO_UPDATE_REPORT_NEW`**: if upstream
  hides the section, babble does too.
- **Doesn't enforce upstream's 100-item ceiling.** When
  `HOMEBREW_NO_INSTALL_FROM_API=1` AND the new-formulae list
  exceeds 100 items, upstream prints bare tokens (no
  descriptions); babble fills in by calling `brew desc` per
  bare token. The user pays the per-formula description
  fetch cost (which is exactly what upstream's ceiling
  avoids). Acceptable given the maintainer's intent that
  babble always show descriptions.

### Mixed-mode bifurcation: visual oddness worth noting

When upstream emits some entries with inline descriptions
and babble fills in for others, the user sees a split
layout:

    ==> New Formulae
    foo: description       # upstream provided
    bar: description       # upstream provided
    baz                    # bare; upstream couldn't provide
    quux                   # bare

    ==> ⨀ Babble: descriptions of new formulae
    baz: description fetched by babble
    quux: description fetched by babble

This is honest about the bifurcation — babble doesn't
duplicate descriptions upstream already showed; it only
fills in what's missing. The visual oddness is the price of
honoring both "upstream is authoritative when it speaks"
and "the maintainer wants descriptions for everything."

Alternative considered: **suppress babble's descriptions
section entirely whenever upstream printed any descriptions.**
This avoids the split but means the bare-token entries get
no description (regression vs. the maintainer's intent).
Rejected.

### `BABBLE_FORCE_DESCRIPTIONS` env var

By default, babble respects upstream's emission rules: if
upstream prints descriptions inline, babble doesn't add a
section. If upstream prints bare tokens, babble fills in.

For the maintainer who wants descriptions printed regardless
of upstream's behavior — e.g., to have the descriptions
grouped together at the end of the update phase rather than
interleaved with the new-formulae section — set
`BABBLE_FORCE_DESCRIPTIONS=1` in `~/.config/babble/babble.env`.
When set, babble always emits its dedicated descriptions
section, calling `brew desc` for every entry regardless of
whether upstream already printed one. The cost is per-token
`brew desc` invocations and visual duplication of
descriptions in the output.

Documented in the README as expected behavior in the rare
default-mode case (HOMEBREW_NO_INSTALL_FROM_API + >100 new
items) and as the maintainer-controlled override.

Note: the cleaned-line regex `^\S+: \S` requires both a
non-space token before the colon and a non-space character
after the space. This avoids false positives on lines that
are just `token:` (no description) or just `token: ` (description
is whitespace).

## Inconsistent code style across refactor/modular

The year+ of refactor/modular had multiple iterations and
authors-in-time (the maintainer at different points in their
own learning, plus AI suggestions accumulated). Specific
inconsistencies:

- **Module naming**: some are `MacUtils::*` (BundleLauncher),
  some are `MacOSInterface::*` (DarkMode, DisplayAlert), most
  are top-level (`BrewUpdate`, `BrewUpgrade`, etc.). No
  consistent rule.
- **Method-style mix**: some modules use `class << self` /
  module methods consistently; others mix `def self.foo` and
  `def foo`. `BundleLauncher` for instance has both styles.
- **Open3 invocation patterns**: `Open3.capture3` vs
  `Open3.capture2` vs backticks vs `system()` vs `popen2e`.
  Refactor/modular uses all five at different times.
- **Error messaging idioms**: `$stderr.puts` vs `warn` vs
  `STDERR.puts` (uppercase) vs structured exception classes
  (`OpenLaunchError`). No consistent rule.
- **Logging prefixes**: `[debug]`, `==>`, `⨀=>`, plain text,
  ANSI-color-wrapped strings — used variously.
- **Hash literal styles**: rocket (`=>`) vs symbol shorthand
  vs explicit `Hash[...]`. Refactor/modular mixes all three.
- **YAML loading**: `YAML.load_file` vs `YAML.safe_load(File.read())`
  in different modules.

**Fix (W3):** The external-command rewrite enforces consistency
by construction:

- Single namespace: `Babble::*` (no sub-namespaces)
- `module Foo; class << self; def bar; end; end; end` consistently
- All subprocess invocation through `Babble::Sh` (or directly
  via Homebrew's `SystemCommand::Mixin`)
- Logging via `Babble::Log` (which delegates to
  `oh1`/`ohai`/`opoo`/`ofail` with `⨀` prefix)
- Symbol shorthand for hash keys
- `YAML.safe_load(File.read(path))` consistently

`brew style` enforces most of this automatically.

## Inconsistent nomenclature

Variable and method names varied across iterations:

- `running_apps` vs `running_gui_bundle_ids` vs
  `initially_running_apps` vs `set_running_apps` (some are
  states, some are functions; the names blur the distinction)
- `casks_to_quit_and_reopen` vs `casks_to_quit` vs `apps_to_quit`
- `bundle_ids` (in config) vs `bundleId` (in some Ruby code,
  matching mas's JSON field)
- `token` (Homebrew term) vs `name` (mas term) vs `cask_name` —
  used overlappingly

**Fix (W3):** Use Homebrew's nomenclature where applicable
(`token` for cask identifier, `app_id` for mas identifier,
`bundle_id` for CFBundleIdentifier value). State variables
get `_state` or `_at_start` suffixes when they're snapshots.
`brew style` plus a maintainer pass on naming.

## Heavy commented-out code in refactor/modular

Refactor/modular has substantial blocks of commented-out
"alternative implementation" code, particularly in
`brew_upgrade.rb`'s `run_upgrade_process`. The block at the
bottom is ~200 lines of commented-out alternative logic that
was preserved during iteration but never deleted.

This was useful for the maintainer's own iteration but adds
cognitive load for future readers.

**Fix (W3):** External-command rewrite starts fresh; no
commented-out code carries forward. Git history is the
preservation mechanism for "what we tried before."

## refactor/modular ships pre-built Swift binaries

`refactor/swift/build/dist/quit_alert_arm64` and `_x86_64`
are committed to the branch. Running them works on the
maintainer's local machine because the local files don't
carry the `com.apple.quarantine` xattr. For distribution,
they're broken (Gatekeeper rejects ad-hoc-signed binaries).

**Fix (W3):** Auto-compile via `xcrun swiftc` on first run.
See `adrs/0001-swift-quit-alert-build-strategy.md` for the
full rationale.

## refactor/modular ships base64-encoded image assets

`refactor/swift/assets/*.png_base64.txt` and
`*.svg_base64.txt` files exist as workarounds for embedding
binary assets in source (the strategy was to compile them
into the Swift binary as base64 string literals). This was
necessary for the pre-built distribution model.

**Fix (W3):** Drop the base64-encoded assets. The
auto-compiled Swift binary reads SVG icons from the babble
tap's `assets/` directory at runtime (via the icon-path
argument). No build-time embedding.

## Quit_message handling block has duplicate logic

In `refactor/ruby/lib/brew_upgrade.rb#validate_config`, the
`quit_message` handling for homebrew entries has duplicate
code:

```ruby
if entry.key?("quit_message")
  valid_entry["quit_message"]                           # no-op statement
  entry["quit_message"].to_s                            # no-op statement
  if existing_value && (existing_value != new_value)    # references undefined variables
    conflicts << "Conflicting 'quit_message' values for cask #{token}"
  end
  valid_entry["quit_message"] ||= new_value.to_s        # references undefined new_value
end
```

This block is broken — `existing_value` and `new_value` are
never assigned. The parallel block for `unsafe_to_quit` does
assign them; the `quit_message` block's first two statements
are stub no-ops where the assignment should be.

The mas entry's parallel block does it differently:

```ruby
if entry.key?("quit_message")
  if valid_mas_entry["quit_message"] && (valid_mas_entry["quit_message"] != entry["quit_message"])
    conflicts << "Conflicting 'quit_message' values for MAS app #{app_id} - #{entry["name"]}"
  end
  valid_mas_entry["quit_message"] ||= entry["quit_message"].to_s
end
```

The mas version works; the homebrew version doesn't.

**Fix (W3):** External-command rewrite drops the homemade
validation in favor of a validator class with proper sigs and
DRY structure. Probably:

```ruby
def merge_optional_field(target, source, field, conflicts:)
  return unless source.key?(field)
  if target[field] && target[field] != source[field]
    conflicts << "Conflicting '#{field}' values for #{describe(source)}"
  end
  target[field] ||= source[field].to_s
end
```

Used uniformly for `unsafe_to_quit`, `quit_message`, and
future optional fields.

## Retry-with-bootsnap-cleanup not ported

The original ksh `bbl` had a `repeat_command` function that
retried `brew upgrade` up to 10 times, clearing
`~/Library/Caches/Homebrew/bootsnap` between attempts. Added in
response to transient bootsnap-cache corruption issues
discussed in
[Homebrew/brew#5226](https://github.com/orgs/Homebrew/discussions/5226).

Refactor/modular's `brew_upgrade.rb` does NOT have this loop.
A code comment marks it as a regression to be addressed.

**Fix (W3):** Implement `Babble::Retry.with_retry`. Wraps
`brew upgrade` (and possibly `brew update`) invocations:

```ruby
Babble::Retry.with_retry(max: 10) do
  result = Homebrew::Cmd::Upgrade.new([...]).run
  if !result
    clear_bootsnap_cache  # Pathname("~/Library/Caches/Homebrew/bootsnap").rmtree if exists
  end
  result
end
```

## brew bundle/Brewfile location migration not handled gracefully

`refactor/ruby/lib/brew_update.rb` includes a `BrewfileMover`
module that atomically moves `~/.Brewfile` →
`~/.config/homebrew/Brewfile`. Useful for the maintainer but
introduces a one-shot side effect that babble shouldn't
silently perform on first run.

**Fix (W3):** Drop the BrewfileMover entirely from babble's
scope. If users want this, they can do it manually (or
Homebrew may eventually do it on their behalf). Babble doesn't
own the user's Brewfile location.

## ANSI-escape stripping is brittle

`BrewUpdate#strip_ansi_escape_sequences` uses a regex with
hand-curated character ranges:

```ruby
text.gsub(%r{\e\[[0-9:;<=>?]*[ !\"#$%&'()*+,-./]*[@A-Za-z\\^_`{|}~]}, "")
```

Real-world ANSI escape sequences include CSI sequences (the
above), OSC sequences (rarer in `brew` output), DCS, and so
on. The regex covers most CSI; it likely misses some.

**Fix (W3):** Either disable ANSI in brew's output via
`HOMEBREW_NO_COLOR=1` for the captured invocation, then
re-enable for the user-facing print, OR use a battle-tested
gem (e.g., `ansi-string`) for stripping. The first is simpler.

## macOS updates: EULA acceptance and restart handling

`refactor/ruby/devel/macos_updates-v4-refactor.rb` (the most
recent iteration, promoted to `lib/macos_updates.rb` locally)
has multiple unresolved issues:

### Issue 1 — `cannot load such file -- logger`

The file fails at startup with:

```
./refactor/ruby/devel/macos_updates-v4-refactor.rb:6:in 'Kernel#require':
  cannot load such file -- logger (LoadError)
```

Ruby 3.5 (and 3.4 since some intermediate point) extracted
`logger` from stdlib to a separate gem. The script's
`require "logger"` fails on systems where the gem isn't
installed.

**Fix (W3):** As an external command, babble inherits
Homebrew's logger if it needs one (Homebrew has its own
built-in `Tty.bold` etc.). Or just don't use `logger` at
all — use plain `$stderr.puts` and Homebrew's formatter
helpers. The W3 implementation drops the `require "logger"`
entirely.

### Issue 2 — EULA acceptance from CLI is unreliable

`softwareupdate --install --all` requires interactive EULA
acceptance for some updates (notably major macOS upgrades
and Xcode-related updates). The CLI doesn't provide a clean
way to pre-accept EULAs:

- `softwareupdate --agree-to-license` exists but doesn't
  cover all cases
- Some updates always require GUI acceptance regardless
- GUI scripting (osascript / JXA) to click "I Agree" buttons
  is fragile across macOS versions and triggers accessibility
  permission prompts

The maintainer's notes flag this as unresolved.

**Fix (W3): bifurcate based on restart-required detection.**

The `softwareupdate --list --include-config-data` output
marks restart-required updates with `Action: restart,` (or
`Action: shut down,`) in the per-update Title line. Sample
output:

```
* Label: macOS Ventura 13.5.1-22G90
    Title: macOS Ventura 13.5.1, Version: 13.5.1, Size: 1520555KiB, Recommended: YES, Action: restart,

* Label: MRTConfigData_10_15-1.93
    Title: MRTConfigData, Version: 1.93, Size: 4595KiB, Recommended: YES,
```

Detection logic:

```ruby
output = `/usr/sbin/softwareupdate --list --include-config-data 2>&1`
restart_required = []
non_restart = []

output.scan(/^\* Label: (.+?)\n\s+Title: (.+)$/m).each do |label, details|
  if details.include?("Action: restart") || details.include?("Action: shut down")
    restart_required << label.strip
  else
    non_restart << label.strip
  end
end
```

Routing:
- **Restart-required updates exist**: list them, note that
  GUI installation is required, redirect to Software Update
  settings pane via
  `/usr/bin/open x-apple.systempreferences:com.apple.Software-Update-Settings.extension`,
  exit cleanly
- **Only non-restart updates exist**: install via
  `softwareupdate --install <label> --no-scan` per label
  (or `--install --recommended --no-scan` for all). These
  typically don't require EULA acceptance and complete
  without reboot. Config-data updates (XProtect,
  MRTConfigData, XProtectPayloads) fit this case.

This keeps end-to-end automation for the easy cases and
redirects to GUI only when the CLI path is unreliable.

### Issue 3 — PTY handling for interactive prompts is incomplete

The macos_updates-v4-refactor.rb file has partial PTY
(pseudo-terminal) handling for capturing softwareupdate's
output while keeping its stdin connected for password and
EULA prompts:

```ruby
require "pty"
# ... PTY.spawn, error checking, ...
```

The error-handling paths are incomplete and the abstraction
is fragile.

**Fix (W3):** If we keep some softwareupdate functionality
(per Issue 2 above), use `system` directly for invocations
that need stdin. Don't try to capture-and-relay through PTY.
`softwareupdate -d` (download-only) and similar non-interactive
commands can use the standard subprocess capture. Interactive
commands shell out with stdin connected.

### Issue 4 — Restart handling is the big unknown

Many softwareupdate installs require restart. babble's flow
can't survive the restart — the process dies. Options:

- **Don't trigger restarts from babble**: list
  restart-required updates separately and tell the user to
  install them via the GUI. Keep babble's domain to
  no-restart updates (the bifurcation in Issue 2 above).
- **Use `--restart` and accept that babble won't see results**:
  the upgrade phases that ran successfully are committed;
  the macOS update phase happens last; if it triggers a
  restart, babble's exit code is moot because the process
  dies. Acceptable if framed correctly to the user.
- **Schedule a post-restart resume via launchd**: a
  LaunchAgent that runs `babble --resume` after login.
  Significantly more complexity; out of scope for v0.6.0.

**Recommendation (W3):** the bifurcation from Issue 2 above
resolves this. Restart-required updates redirect to GUI;
babble doesn't try to install them. Non-restart updates
install via `softwareupdate --install` and complete cleanly
without babble dying.

## "Unused #1, Unused #2" comments in base64 NOTES.txt

The `NOTES.txt` from the base64 branch contains two snippets
labeled "Unused #1" and "Unused #2" that document alternative
parsing patterns considered:

```
# Unused #2
# Big thanks to William 'talkingmoose' Smith for this way of parsing lsappinfo
# restart_apps=("$(/usr/bin/lsappinfo list | /usr/bin/awk -F '\\) "|" ASN' 'NF > 1 && tolower($2) ~ /stats/ {print $2}')")

# Unused #1
# restart_apps="$(/usr/bin/lsappinfo info -app eu.exelban.Stats | /usr/bin/awk '$1 == "pid" {print $3}')"; test -n "$restart_apps" && open -b eu.exelban.Stats || :
```

These document approaches that were tried but rejected. Now
preserved permanently here. No action needed; just preservation.

## Configuration validation tests are loose

`refactor/ruby/lib/brew_upgrade.rb` has `test_valid_bundle_id`
and `test_valid_homebrew_token` methods that are run-time tests
(invoked at startup if the script is loaded directly). They use
`raise` for failures rather than a proper test framework.

**Fix (W3):** Real RSpec specs at `spec/babble/config_spec.rb`
or similar. The valid/invalid case lists from refactor/modular
become the spec's `let` blocks. `bundle exec rspec` (or
`brew tests`) replaces the run-time invocation.

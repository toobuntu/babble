<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Architectural decisions

This file consolidates the design decisions made during the
year+ Ruby port and the subsequent planning that led to the
external-command pivot. Each decision: a short rationale, a
code block from `refactor/modular` (or PR #1, where noted)
showing the prior approach, and a brief note on what carries
forward to W3.

Order is roughly outside-in: entry point first, then phase
orchestration, then per-module decisions, then conventions.

## Bash entry point pattern

Refactor/modular's `refactor/bin/babble` initializes the
Homebrew environment, sources `utils/ruby.sh`, and execs Ruby
with the right interpreter. The original ksh `_usr_local_bin_bbl`
that was preserved before the rm-rf used the same pattern.
PR #1's wrapper sourced `cmd/setup-ruby.sh` and called the
higher-level `homebrew-setup-ruby` function — different shape,
similar goal.

```bash
# refactor/bin/babble (excerpt)
initialize_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    HOMEBREW_PREFIX="$(brew --prefix)" || {
      echo "Error: 'brew --prefix' failed." >&2
      exit 1
    }
  fi
}
initialize_homebrew
export HOMEBREW_BREW_FILE="${HOMEBREW_PREFIX}/bin/brew"
export HOMEBREW_LIBRARY="${HOMEBREW_PREFIX}/Library"

. "${HOMEBREW_PREFIX}/Library/Homebrew/utils/ruby.sh"
setup-ruby-path

homebrew_ruby_bin="$(dirname "${HOMEBREW_RUBY_PATH}")"
export PATH="${homebrew_ruby_bin}:${PATH}"

execute_ruby() {
  if [[ -z "${HOMEBREW_DEVELOPER}" ]]; then
    unset HOMEBREW_RUBY_WARNINGS
  fi
  if [[ -z "${HOMEBREW_RUBY_WARNINGS}" ]]; then
    export HOMEBREW_RUBY_WARNINGS="-W1"
  fi
  exec "${HOMEBREW_RUBY_PATH}" "${HOMEBREW_RUBY_WARNINGS}" "${HOMEBREW_RUBY_DISABLE_OPTIONS}" "$@"
}
execute_ruby "$@"
```

**Carries to W3?** No. As an external command, babble runs
inside Homebrew's process; no entry-point wrapper is needed.
The entire entry-point file (and its associated complexity)
disappears under the external-command shape. PR #1 review § S1
proposed a simpler `current/bin/ruby` symlink path, which would
have been the right move for a standalone library — but
external command obviates that too.

## Module decomposition

Refactor/modular split the work into a clean set of modules
under `refactor/ruby/lib/`:

```
brew_cask_utils.rb        # cask token validation, lookup helpers; also served as quarantine purger pre-cask-tools
brew_update.rb            # `brew update` orchestration + parsing
brew_upgrade.rb           # `brew outdated` + `brew upgrade` orchestration
mas_upgrade.rb            # `mas outdated` + `mas upgrade` orchestration
macos_updates.rb          # softwareupdate orchestration
macos_interface/
  dark_mode.rb            # AppleInterfaceStyle detection
  display_alert.rb        # invokes Swift quit_alert binary
ui/
  waiter.rb               # interactive "press space to continue" prompts
utils/
  bundle_launcher.rb      # MacUtils::BundleLauncher (3-tier launcher)
  running_gui_bundle_ids.rb   # lsappinfo-based running-app detection
```

Plus `refactor/ruby/utils/mas_token_generator.rb` (a small
utility for generating the mas-store-style identifiers).

The phase order is roughly: `brew_update` → `brew_upgrade` →
`mas_upgrade` → `macos_updates`. This mirrors the ksh `bbl`
flow and is the structure W3 inherits.

Files that ended up in `lib/` after the maintainer's local
promotion from `devel/`:
- `mas_upgrade.rb` was promoted from
  `refactor/ruby/devel/mas_upgrade-v1.rb` to
  `refactor/ruby/lib/mas_upgrade.rb`
- `macos_updates.rb` was promoted from
  `refactor/ruby/devel/macos_updates-v4-refactor.rb`
  (the local lib/ on disk reflected this; the
  refactor/modular branch tip may show the older versions
  depending on what was last pushed)

**Carries to W3?** Yes, with module renaming. As an external
command, the namespace becomes `Homebrew::Cmd::Babble` for the
entry class and `Babble::*` for substantive modules. The split
between `BrewUpdate`, `BrewUpgrade`, `MasUpgrade`, `MacOSUpdate`,
`AppManager`, `BundleLauncher`, `Waiter`, plus the new
`Config::{Loader, Validator, Reorganizer}` triple and the new
`TerminalDetector`, follows refactor/modular's boundaries with
the configuration concerns extracted to their own namespace.
The `MacUtils::*` and `MacOSInterface::*` namespaces collapse
into `Babble::*` — there's no good reason to maintain
sub-namespaces in a single-purpose external command.

## Module-level imports and dependencies

Refactor/modular used `require_relative` aggressively, with each
module declaring its dependencies explicitly:

```ruby
# refactor/ruby/lib/brew_upgrade.rb (excerpt)
require "English"
require "yaml"
require "open3"
require "json"
require_relative "../ui/waiter"
require_relative "./utils/bundle_launcher"
```

**Carries to W3?** Yes, with idiom adjustment. External commands
in Homebrew typically use `require` rather than `require_relative`
because the load path includes `Library/Homebrew`. The
dependencies stay explicit; only the form changes.

## Configuration schema

Refactor/modular's `unified-config.yml`:

```yaml
apps:
  homebrew:
    - token: adobe-acrobat-reader
      bundle_ids:
        - com.adobe.AdobeRdrCEFHelper
        - com.adobe.Reader
        - com.adobe.Reader.helper
      unsafe_to_quit: false
      quit_message: "Save your PDFs first."   # optional; if absent, default text is used
    - token: stats
      bundle_ids:
        - eu.exelban.Stats
  mas:
    - app_id: 1595464182
      name: MonitorControlLite
      bundle_ids:
        - app.monitorcontrol.MonitorControlLite
      unsafe_to_quit: true
      quit_message: "Apply any pending settings."
```

A TODO comment at the top of unified-config.yml flagged the
asymmetry problem: Adobe Acrobat Reader spawns three bundle IDs
that all need to be quit, but only one (`com.adobe.Reader`)
should be reopened — the helpers spawn themselves when the
main app launches. The flat `bundle_ids` list can't express
this.

**Carries to W3?** With several schema refinements.

### Asymmetric quit/reopen via `bundle_ids.{quit, reopen}`

Adopt independent lists:

```yaml
# Simple case (most apps): flat list, both quit and reopen
- token: stats
  bundle_ids:
    - eu.exelban.Stats

# Asymmetric case (helpers don't auto-restart on parent launch)
- token: adobe-acrobat-reader
  bundle_ids:
    quit:
      - com.adobe.AdobeRdrCEFHelper
      - com.adobe.Reader
      - com.adobe.Reader.helper
    reopen:
      - com.adobe.Reader
  unsafe_to_quit: false
```

Validator normalizes: a flat `bundle_ids: [...]` becomes
`bundle_ids: { quit: [...], reopen: [...] }` where both lists
equal the flat list. No backwards-compat (the only consumer is
the maintainer's `babble.apps.yml`, which gets rewritten in W3).

### `app_id` renamed to `adam_id` (mas alignment)

mas upstream renamed the iTunes Store identifier from `app_id`
to `adam_id` for clarity (`app_id` was being used for both the
adam ID and the bundle ID at different code paths). Babble
follows suit:

```yaml
mas:
  - adam_id: 1595464182          # was: app_id
    name: MonitorControlLite
    bundle_ids: ...
```

Aligns with `mas info <adam_id>` and `mas list --json`'s
output field naming.

### `quit_handling` nests the elaboration for `unsafe_to_quit: true` apps

When `unsafe_to_quit: true`, babble may need additional
behavior beyond the boolean: which confirmation mechanism to
use, what message text to show, and a timeout. These nest
under `quit_handling`:

```yaml
- token: adobe-acrobat-reader
  bundle_ids:
    quit:    [com.adobe.AdobeRdrCEFHelper, com.adobe.Reader, com.adobe.Reader.helper]
    reopen:  [com.adobe.Reader]
  unsafe_to_quit: true
  quit_handling:
    confirm: gui                            # gui | terminal | silent; default: terminal
    quit_message: "Save your PDFs first."   # optional; replaces the default text
    timeout_seconds: 30                     # optional; how long to wait for user response
```

Fields nested under `quit_handling`:

- **`confirm`**: `gui` | `terminal` | `silent`. Default:
  `terminal`. `gui` triggers the Swift quit_alert binary (or
  its osascript fallback if Swift compilation fails).
  `silent` skips the prompt entirely — the app is logged but
  not interactively confirmed before quitting. `terminal` is
  the default `gets`-based prompt.
- **`quit_message`**: optional string; replaces the default
  prompt text ("Please save your work in <app_name> before
  continuing.").
- **`timeout_seconds`**: optional integer; how long to wait
  for user response before falling through (treats no response
  as "continue"). Useful for apps where the user explicitly
  configured `confirm: gui` and may not be at the keyboard.
  Default: no timeout (block forever).

`quit_handling` itself is optional. When `unsafe_to_quit:
true` without `quit_handling`, defaults apply
(`confirm: terminal`, default message, no timeout). When
`unsafe_to_quit: false` (or absent), `quit_handling` is
ignored if present.

### Schema in full

```yaml
apps:
  homebrew:
    - token: <cask_token>
      bundle_ids:
        # Flat shorthand:
        - <CFBundleIdentifier>
        # OR structured for asymmetric quit/reopen:
        # quit:   [<id>, ...]
        # reopen: [<id>, ...]
      unsafe_to_quit: <bool>          # default: false
      quit_handling:                  # optional; only relevant if unsafe_to_quit: true
        confirm: <gui|terminal|silent>     # default: terminal
        quit_message: <string>             # optional override of default text
        timeout_seconds: <integer>         # optional; default: no timeout
  mas:
    - adam_id: <integer>              # iTunes Store adam ID; was: app_id
      name: <string>
      bundle_ids:
        # same flat-or-structured shape as homebrew
        - <CFBundleIdentifier>
      unsafe_to_quit: <bool>
      quit_handling: ...              # same shape as homebrew
```

### File naming: `babble.apps.yml`

The filename `unified-config.yml` is generic. Better:
`babble.apps.yml` — namespaced by tool, descriptive of
content.

This isn't a config file (settings); it's an operational
manifest (declarative metadata about which apps to manage in
the upgrade lifecycle). The `babble.apps.yml` form mirrors
Homebrew's project-namespaced files (`Brewfile`, `Vagrantfile`,
`Procfile`).

The lookup chain accepts both `babble.apps.yml` and the
dot-prefixed `.babble.apps.yml`. Dot-prefixed wins if both
exist (same convention as `.gitignore`).

The legacy filenames `unified-config.yml` and `.babblefile.yml`
retire entirely.

## Configuration lookup chain

Refactor/modular used a hardcoded `unified-config.yml` in the
project root. PR #1 made the path configurable via `--config-file`.
Neither implemented the Homebrew-style first-match-wins lookup
chain.

**Carries to W3?** Yes, properly. The lookup chain combines
an environment override, a Brewfile-style upward directory
walk from cwd, and a fall-through to user-/system-wide
locations:

1. **`$BABBLE_APPS`** — path override; respected absolutely
   if set
2. **Walking up from cwd**: at each directory, check for
   `.babble.apps.yml` first (dot-prefixed wins) then plain
   `babble.apps.yml`. First match wins. Stop at the
   filesystem root or `$HOME` (whichever is shallower). This
   matches Homebrew's `Brewfile` discovery pattern (e.g.,
   `brew bundle` walks up looking for `Brewfile`).
3. **`${XDG_CONFIG_HOME:-$HOME/.config}/babble/babble.apps.yml`**
4. **`$HOME/.babble.apps.yml`**
5. **`/etc/babble/babble.apps.yml`**

**Naming convention.** The filename is `babble.apps.yml`
everywhere — inside `babble/` namespace directories as well
as standalone. Self-identifying when extracted, copied, or
found via `mdfind`/`find`. Reading the bare filename is
enough to know what it is; the directory context isn't
required for disambiguation.

The dot-prefixed form `.babble.apps.yml` is accepted in
the upward-walk locations (cwd and ancestors) for users
who prefer hidden files, following the convention of
`.gitignore` etc. The plain form is the default.

**Why upward walk instead of fixed git-repo-root?** Homebrew's
`Brewfile` discovery walks up from cwd regardless of git
repository structure; this matches how users naturally
organize files (a project directory may not be a git repo,
or may be a subdirectory of one). The walk stops at `$HOME`
or `/` to avoid silently finding files in unexpected
ancestor directories.

Mirrors how Homebrew finds its own config. The example file
ships in the tap as `config/babble.apps.example.yml`, and
the maintainer's actual config lives in
`~/.config/babble/babble.apps.yml`, not committed to the
repo.

## User-tunable settings: `babble.env` (mirrors Homebrew's `brew.env`)

Babble has a few env-var-style tunables that are persistent
user preferences rather than per-invocation flags. Examples:

- `BABBLE_FORCE_DESCRIPTIONS` — always emit the descriptions
  section after `brew update`, even when upstream printed
  inline descriptions or skipped them due to the >100-item
  ceiling under `HOMEBREW_NO_INSTALL_FROM_API=1`
- `BABBLE_QUIET` — reduce verbosity (TBD)
- `BABBLE_CONFIRM_DEFAULT` — default `confirm:` value when
  apps' `quit_handling.confirm` is unset (one of `gui`,
  `terminal`, `silent`); defaults to `terminal`

**Carries to W3?** Yes, via a `babble.env` file parallel to
Homebrew's `brew.env`.

```
# ~/.config/babble/babble.env
BABBLE_FORCE_DESCRIPTIONS=1
BABBLE_CONFIRM_DEFAULT=gui
BABBLE_QUIET=1
```

Lookup order:

1. Process environment (set by user shell, command-line
   prefix, or parent process) — always wins
2. `${XDG_CONFIG_HOME:-$HOME/.config}/babble/babble.env`
3. `/etc/babble/babble.env`

No upward directory walk for `babble.env` — these are user
preferences, not per-project settings. The settings travel
with the user, not with the directory.

**Format**: shell-source-compatible `KEY=VALUE` pairs, one
per line. Comments start with `#`. No quoting required for
simple values; double-quotes for values with spaces. Babble
reads the file and sets `ENV[key] = value` for each pair
before phase orchestration begins; CLI flags override.

**Why not a `settings:` section in `babble.apps.yml`?**

- Mixing operational metadata (which apps to manage) with
  user preferences (how chatty babble is) muddies the file's
  purpose
- Users syncing `babble.apps.yml` across machines via dotfiles
  may want different settings per machine; the env-var path
  separates these concerns naturally
- The maintainer's existing pattern (HOMEBREW_* in
  `~/.config/homebrew/brew.env`) already establishes the
  convention

**Why not require all settings be set in the shell init?**

- The maintainer's stated preference is `~/.config/homebrew/brew.env`
  over `~/.zshrc` for tool-specific env vars; following the
  same convention is consistent
- A dedicated env file is also easier to back up, share with
  collaborators, or version-control independently of the
  shell init
- Per-invocation overrides via CLI flags or `BABBLE_FOO=1
  babble` still work — the env file is just one input

## Multi-file config merge with conflict reporting

Refactor/modular's `devel/config_merge.rb`,
`devel/config/loader.rb`, and `devel/config/loader-v2.rb`
implement multi-file merge: load configs from several
locations, deep-merge them in priority order, and report
conflicts where two sources disagree on the same field. The
merge logic is field-aware:

- `bundle_ids` lists — set union (deduplicated)
- `unsafe_to_quit` boolean — logical OR (any-true wins),
  with a warning when sources disagree
- `quit_message` string — higher-priority source wins, with
  a warning if sources disagree
- `name` (mas only) — higher-priority source wins, with a
  warning if sources disagree

Key snippet (`devel/config/loader.rb`):

```ruby
def self.deep_merge_entries(old_entry, new_entry, section)
  merged = old_entry.dup

  if section == "homebrew"
    # Merge bundle_ids (union and deduplication).
    merged["bundle_ids"] = (old_entry["bundle_ids"] + new_entry["bundle_ids"]).uniq

    # For unsafe_to_quit: using conservative merge (true if any source is true).
    if old_entry["unsafe_to_quit"] != new_entry["unsafe_to_quit"]
      $stderr.puts("Warning: Conflict for Homebrew token #{old_entry['token']} on unsafe_to_quit – defaulting to true.")
    end
    merged["unsafe_to_quit"] = old_entry["unsafe_to_quit"] || new_entry["unsafe_to_quit"]
    # ... similar for bypass_gatekeeper, quit_message ...
  end
  merged
end
```

The merge runs at startup. Per-file `Reorganizer.reorder_file`
call (yq) sorts each source file in place before merge. The
merged result is cached in `${TMPDIR}/merged_bundlefile.yml`
with mtime-based freshness checking; cleanup via `at_exit`
and SIGINT/SIGTERM handlers.

The verbose conflict warnings printed to stderr are why
the maintainer ran `./refactor/ruby/lib/brew_upgrade.rb 2>
/dev/null` during daily use — each conflict produced one
stderr line per field per duplicate key.

**Status**: this design was fully implemented in `devel/`
but never promoted to `lib/`. The maintainer was still
iterating on the merge-conflict semantics (the v1 vs. v2
loaders show two design rounds).

**Carries to W3?** Yes — the multi-file merge is a real
feature worth keeping. Refinements:

- **Update the field-merge rules for the new schema.**
  `bypass_gatekeeper` is gone (delegated to
  cask-tools' `purge-quarantine`). `quit_message` moves
  under `quit_handling`. Add merge rules for the new
  `quit_handling.{confirm, timeout_seconds}` fields.
- **Schema migration**: when merging, if `quit_handling`
  is unset on one side and set on the other, the set value
  wins (no conflict). When both sides set `quit_handling`,
  recurse into per-field merge with conflict reporting.
- **Quieter conflict reporting.** Collapse multiple field
  conflicts on the same app into a single warning per app
  instead of one per field. The 1-per-app summary makes the
  output skimmable: `"⨀ Babble: warning: token X has
  conflicts on quit_message, unsafe_to_quit; using
  higher-priority source"`.
- **Validate-then-merge.** Each source file gets validated
  via `Babble::Config::Validator` before merge. Invalid
  entries are dropped from their source (with a warning) so
  they don't pollute the merged config. The Validator's
  result also feeds the conflict report ("app X is
  invalid in source Y; ignored").
- **Cache the merged result with mtime check** the same way
  refactor/modular does. The cache lives in
  `${HOMEBREW_CACHE}/babble/merged_apps.yml`; cleanup via
  Homebrew's normal cache rotation (no `at_exit` handler
  needed).
- **Document the priority order** in the README so users
  understand which source wins.

This becomes a primary responsibility of `Babble::Config`,
specifically the new `Babble::Config::Merger` (sibling to
`Loader`, `Validator`, `Reorganizer`):

- `Loader` finds and parses each source file, returning raw
  hashes
- `Validator` checks each source's validity, returning
  per-source validation results
- `Merger` consumes validated sources and produces a merged
  config with conflict reports
- `Reorganizer` sorts and dedupes the merged result via yq

The four-module split is consistent with refactor/modular's
intent (which had `Reorganizer` as a separate file and
`Loader` doing both loading and merging). Splitting `Merger`
out makes the merge semantics independently testable.

## Homebrew token validation

Refactor/modular's regex includes pinned-version syntax:

```ruby
# refactor/ruby/lib/brew_upgrade.rb
def self.valid_homebrew_token?(token)
  token.match?(/^[a-z0-9]+(-[a-z0-9]+)*(@[a-z0-9.-]+)?$/)
end
```

Test cases (also in refactor/modular):

```ruby
valid_cases = ["example-token", "token", "token-with-hyphens",
               "token@1.2.3", "token@nightly"]
invalid_cases = ["Token", "TOKEN", "token_with_underscore",
                 "token@invalid!", "token@1.2@3", "-token", "token-"]
```

**Carries to W3?** Yes, but as direct API call. As an external
command, babble can call `Homebrew::Cask::Cask.casks` to check
whether a token corresponds to a real cask, rather than rolling
its own regex validation. Useful for catching typos in apps.yml.
The regex stays as a syntactic pre-filter; the API check
confirms the token actually exists.

## App quit via JXA

Refactor/modular's `quit_app`:

```ruby
# refactor/ruby/lib/brew_upgrade.rb
def self.quit_app(bundle_id, config_entry)
  if config_entry["unsafe_to_quit"]
    puts config_entry["quit_message"] || "Please save your work in the application before continuing."
    puts "Press Enter when ready to quit the application."
    gets
  end

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
            $.NSFileHandle.fileHandleWithStandardError.writeData(
                $.NSString.alloc.initWithUTF8String("Application with Bundle ID: #{bundle_id} is not running.\\n").dataUsingEncoding($.NSUTF8StringEncoding)
            );
        }
    } catch (error) {
        $.NSFileHandle.fileHandleWithStandardError.writeData(
            $.NSString.alloc.initWithUTF8String("Error while processing Bundle ID: #{bundle_id}. " + error.toString() + "\\n").dataUsingEncoding($.NSUTF8StringEncoding)
        );
    }
    undefined;
  EOS

  stdout, stderr, = Open3.capture3("osascript -l JavaScript", stdin_data: jxa_script)
  BrewUpgrade.handle_quit_result(stdout, stderr, bundle_id)
end
```

Why JXA over `osascript -e 'tell app id "..." to quit'`: proper
exception handling with try/catch; structured output via
NSFileHandle; reliable error attribution (which bundle ID
failed and why). The osascript approach reports failures as
opaque strings.

**Carries to W3?** Yes, but with the `quit-and-reopen` schema
distinction. The orchestrator decomposes into:

1. Check whether bundle is in `bundle_ids.quit` or
   `bundle_ids.reopen` (or implicitly both via the flat-list
   shorthand).
2. If in `quit` and currently running, invoke JXA quit.
3. If in `reopen` and was previously running, invoke
   bundle_launcher reopen post-upgrade.

The asymmetry handles helpers cleanly: `com.adobe.AdobeRdrCEFHelper`
is in `quit` only; it gets quit but never reopened. When the main
app launches, the helper spawns itself.

## Bundle launcher (three-tier in refactor/modular; seven-tier in cask-tools)

Refactor/modular's `MacUtils::BundleLauncher`:

```ruby
# refactor/ruby/lib/utils/bundle_launcher.rb (~257 lines, excerpted)
def self.launch(bundle_id, timeout: 10)
  bundle_id = sanitized_bundle_id(bundle_id)
  run_open(bundle_id)
  wait_until_reopened(bundle_id, timeout)
  true
rescue OpenLaunchError => e
  # Resolve path for targeted re-registration
  path = app_path_via_mdfind(bundle_id) || app_path_via_lsregister_dump(bundle_id)
  if path && File.directory?(path)
    force_ls_registration(path)
    run_open(bundle_id)
    wait_until_reopened(bundle_id, timeout)
  end
end
```

Three-tier: `mdfind` → `lsregister -dump` → walker (with
`PlistBuddy` validation of `CFBundleIdentifier`). Plus retry-with-backoff
on the initial `/usr/bin/open` (`attempts < tries; sleep 0.15 * attempts`).
Plus launchctl-asuser fallback for GUI session inheritance.
Plus a custom `OpenLaunchError` class with `to_h` for diagnostics.

**Carries to W3?** Yes, but consuming the seven-tier
`Homebrew::Cask::BundleDiscovery` helper from cask-tools (W7
in master-plan). The retry-with-backoff and launchctl-asuser
fallback stay; the path-resolution tiers delegate.

## Light/dark mode detection for Swift quit_alert

Refactor/modular's `MacOSInterface::DarkMode`:

```ruby
# refactor/ruby/lib/macos_interface/dark_mode.rb (full file)
require "open3"

module MacOSInterface
  class DarkMode
    def self.enabled?
      stdout, status = Open3.capture2("defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null")
      status.success? && stdout.strip == "Dark"
    end
  end
end
```

`AppleInterfaceStyle` defaults to absent (light mode); is set
to `"Dark"` when dark mode is active. The `2>/dev/null`
suppresses the "key does not exist" error when in light mode.

**Carries to W3?** Yes, simplified. As an external command,
this becomes a small helper in `Babble::Formatter` (or wherever
the Swift quit_alert invocation lives). One method, ~5 lines.

## Swift quit_alert build strategy

Refactor/modular shipped pre-compiled architecture-specific
binaries: `swift/build/dist/quit_alert_arm64` and
`quit_alert_x86_64`. The Ruby orchestrator
(`MacOSInterface::DisplayAlert`) detected architecture and
called the right binary.

The PR #1 implementation noted that ad-hoc-signed binaries
fail Gatekeeper on Apple Silicon (no Apple Developer cert →
no codesign → can't distribute). It pivoted to auto-compiling
on first run via `xcrun swiftc`.

**Carries to W3?** Auto-compile pattern wins. See
[`adrs/0001-swift-quit-alert-build-strategy.md`](adrs/0001-swift-quit-alert-build-strategy.md)
for the full ADR. Refactor/modular's pre-compile approach is
documented as superseded.

## yq-based config sorting and dedup detection

Refactor/modular used `yq` to alphabetically sort the config
file and detect duplicates. This was deliberate: pure-Ruby
`Psych` (Ruby stdlib YAML) parses comments OUT of the document
on load and cannot emit them on dump. A round-trip via Psych
silently destroys user comments. yq, by contrast, preserves
comments natively.

```ruby
# refactor/ruby/lib/brew_upgrade.rb#reorganize_config_file (excerpt)
sorted_content = `yq eval '
  .apps.homebrew |= sort_by(.token) |
  .apps.mas |= sort_by(.name) |
  (.apps.homebrew[].bundle_ids |= sort) |
  (.apps.mas[].bundle_ids |= sort)
' #{file_path}`
data = YAML.safe_load(sorted_content)

homebrew_duplicates, mas_duplicates = check_duplicates(data)

if homebrew_duplicates.any? || mas_duplicates.any?
  $stderr.puts "Warning: Duplicates detected in YAML file."
  # ... print details, exit 1
end
```

The reorganization runs at startup if `yq` is available; it's
a no-op otherwise.

### `psych-pure` is unavailable in third-party taps

Kevin Newton's [`psych-pure` gem](https://github.com/kddnewton/psych-pure)
(announced at https://kddnewton.com/2025/12/25/psych-pure.html)
is a pure-Ruby YAML parser that DOES preserve comments through
round-trips. On the surface, it would let babble drop the yq
shell-out.

In practice, **Homebrew only allows dev-cmds to install gems**.
External commands in third-party taps cannot install gems
(this constraint also affected `generate-tap-man-completions`
in `homebrew-cask-tools` — the workaround was to hardlink it
into Homebrew's `dev-cmd/` directory, which is hacky and
unmaintainable). Without psych-pure, comment-preserving YAML
round-trips require either:

- An external tool (yq) at runtime, or
- Manual byte-level patching of YAML strings, or
- Skipping the round-trip entirely

**Carries to W3?** Keep auto-reorganize-on-startup.

Reasoning:
- The maintainer's daily-use experience benefits from auto-sort
  (it's how the original ksh+yq workflow worked for the year+
  of refactor/modular)
- A subcommand the user has to remember to invoke is friction
  that effectively disables the feature for most users
- The alternative ("add annoying messaging that encourages the
  user to run the subcommand") requires writing the same
  parsing+detection code as auto-reorganize, plus the prompt,
  for less benefit

yq becomes a runtime dependency declared in babble's Homebrew
formula via `depends_on "yq"`. Installation pulls yq
automatically. If yq is somehow missing at runtime (manually
uninstalled), babble emits a one-line `opoo` and skips the
reorganize for that run; the user's data is preserved either
way.

Duplicate detection runs unconditionally on every startup
using stdlib `Psych` (parse-only operations don't risk
comment destruction; the round-trip is what requires yq).

For the full rationale on why yq over Psych over psych-pure,
see [`adrs/0002-yaml-handling-yq-vs-psych-vs-psych-pure.md`](adrs/0002-yaml-handling-yq-vs-psych-vs-psych-pure.md).

## brew update via `brew update-if-needed`

Refactor/modular's `update_if_needed`:

```ruby
# refactor/ruby/lib/brew_upgrade.rb
def self.update_if_needed
  system("brew", "update-if-needed")
end
```

This delegates to Homebrew's own staleness gate (which respects
`HOMEBREW_AUTO_UPDATE_SECS` and similar). PR #1 invented a
parallel touch-file timer, which was a regression — it lost
Homebrew's environment-variable controls.

**Carries to W3?** Yes, with `safe_system HOMEBREW_BREW_FILE`.
Homebrew/brew's own `AGENTS.md` instructs:

> Prefer shelling out via `HOMEBREW_BREW_FILE` instead of
> requiring `cmd/` or `dev-cmd` when composing brew commands.

Applied throughout babble:

```ruby
safe_system HOMEBREW_BREW_FILE, "update-if-needed"
safe_system HOMEBREW_BREW_FILE, "outdated", *args
safe_system HOMEBREW_BREW_FILE, "upgrade", *args
safe_system HOMEBREW_BREW_FILE, "desc", "--formula", token
```

This is also the pattern used by `Reporter#migrate_tap_migration`
in `Library/Homebrew/cmd/update-report.rb` (`system
HOMEBREW_BREW_FILE, "install", new_full_name`).

The split: **read state via Ruby APIs**
(`Formula.installed`, `Cask::Caskroom.casks`,
`Cask::CaskLoader`); **mutate state via
`safe_system HOMEBREW_BREW_FILE`** for `install`/`upgrade`/
`update`/etc. Direct API calls to `Homebrew::Cmd::Upgrade.new(...).run`
are avoided per the AGENTS.md rule — this avoids hard
coupling to `cmd/` and `dev-cmd/` internals that Homebrew
reserves the right to refactor.

## Retry with bootsnap-cache cleanup

The ksh original wrapped `brew upgrade` in a `repeat_command`
loop. Up to 10 attempts; between attempts, clear
`~/Library/Caches/Homebrew/bootsnap`. Added in response to
[Homebrew/brew discussion #5226](https://github.com/orgs/Homebrew/discussions/5226)
about transient bootsnap-cache corruption.

Refactor/modular's `brew_upgrade.rb` did not port this loop —
the comment in `run_upgrade_process` notes it as a regression
to be addressed.

**Carries to W3?** Yes. New `Babble::Retry.with_retry` helper:

```ruby
module Babble
  module Retry
    def self.with_retry(max:, on_fail:)
      attempts = 0
      loop do
        result = yield
        return result if result
        attempts += 1
        break if attempts >= max
        on_fail.call(attempts)
      end
      nil
    end
  end
end
```

Used in `BrewUpgrade#upgrade_packages` as
`Babble::Retry.with_retry(max: 10, on_fail: ->(_n) { clear_bootsnap_cache }) { brew_upgrade_invocation }`.

## lsappinfo parsing for running-app detection

Refactor/modular's `set_running_apps`:

```ruby
# refactor/ruby/lib/brew_upgrade.rb
def self.set_running_apps
  stdout, status = Open3.capture2(
    "/usr/bin/lsappinfo list | " \
    "/usr/bin/awk -F'\"' '/bundleID/{print $2}' | " \
    "/usr/bin/sort -u",
  )
  if status.success?
    stdout.strip.empty? ? [] : stdout.split("\n").compact
  else
    $stderr.puts "Error getting running apps."
    []
  end
end
```

The `awk -F'"' '/bundleID/{print $2}'` pattern is the working
extraction. PR #1's regex
`/"CFBundleIdentifier"="([^"]+)"/` never matched (lsappinfo
emits `bundleID="..."`, not `CFBundleIdentifier="..."`).

**Carries to W3?** Yes. Refactor/modular's working pattern
ports directly. As an external command, the function becomes
a method on `Babble::AppManager` and uses Homebrew's
`SystemCommand::Mixin` rather than `Open3.capture2`.

## Mac App Store: mas v7 JSON

Refactor/modular's `mas_upgrade-v1.rb` (in `refactor/ruby/devel/`)
parsed `mas outdated` text output. mas v7.0 (released earlier
this year) added `--json` to `list`, `outdated`, `search`,
`lookup`/`info`, and `config`.

**Carries to W3?** Yes. New `MasUpgrade` parses
`mas outdated --json`. Eliminates the maintain-bundle-IDs-in-config
work for mas apps — `mas list --json <app_id>` returns
`bundleID` directly.

## Output formatting: ⨀ prefix on Homebrew helpers (option 2)

Two competing approaches considered:

**Option 1 — Custom helpers with custom color.** Define
`babble_oh1` / `babble_ohai` / etc., mirroring Homebrew's
functions but emitting in cyan instead of magenta.
Distinguishes by **color**.

**Option 2 — Use Homebrew helpers; prefix message with `⨀`.**
Call `oh1 "⨀ Babble message"`, producing
`==> ⨀ Babble message`. Distinguishes by **symbol**.

refactor/modular took a third approach in some places: raw
ANSI codes (`\033[36m⨀=> \033[0m\033[1m...\033[0m`) for cyan
`⨀=>`. This was a partial implementation — the cyan only
appeared in a few `puts` calls, not in `opoo` or `ofail`. So
in practice, refactor/modular's output mixed cyan-`⨀=>`,
plain `==>` (Homebrew-via-shell-out), and bareword text.
The distinction was incomplete.

**Carries to W3?** Option 2.

```ruby
oh1   "⨀ Babble: Phase 1 — Update Homebrew"
ohai  "⨀ Quitting Stats..."
opoo  "⨀ Skipping iterm2 (running terminal)"
ofail "⨀ Failed to launch Stats after upgrade"
```

Reasoning:
- **Homebrew's `oh1` and `ohai` provide the visual hierarchy**
  by their existing size/position conventions — we don't
  reinvent them by switching to a custom-color implementation
- **The `⨀` prefix is sufficient** to identify babble's output
  vs. Homebrew's; color isn't necessary for distinguishability
- **Custom color (cyan) would require custom helpers**
  (`babble_oh1`, `babble_ohai`) to maintain the size/position
  hierarchy, adding maintenance burden
- **Severity colors come for free**: `opoo` is yellow, `ofail`
  is red. Babble's prefix integrates with Homebrew's severity
  scheme.
- **`HOMEBREW_NO_COLOR` and TTY detection are respected**
  through `oh1`/`ohai`/etc. directly; no custom path

The `⨀` prefix on the message text identifies babble's
output regardless of severity. Reading
`==> ⨀ Babble: Phase 1` next to `==> Updated 1 tap` makes
the difference unambiguous — the unicode glyph stands out
even without color contrast.

refactor/modular's cyan ANSI codes are **not preserved** in
W3. The earlier coding inconsistency (cyan-`⨀=>` mixed with
plain `==>` mixed with bareword) gets cleaned up to a uniform
Homebrew-helpers-with-`⨀`-prefix pattern.

## Sorbet typing discipline

Refactor/modular's modules carry `# typed: strict` and
`# frozen_string_literal: true` headers. Sigs are commented
out (Sorbet not actively enforced in the year+ work, but the
shape is ready).

**Carries to W3?** Yes, with active enforcement. As an
external command, babble inherits Homebrew's Sorbet
configuration. `# typed: strict` files in the babble code
get checked in CI via `brew typecheck` (works because the
file is linked into Homebrew's `cmd/` for CI). Sigs become
real:

```ruby
sig { params(bundle_id: String, timeout: Integer).returns(T::Boolean) }
def self.launch(bundle_id, timeout: 10)
  ...
end
```

## REUSE/SPDX compliance

Refactor/modular did not have SPDX headers throughout. The
license is GPLv3, but per-file attribution was sparse.

**Carries to W3?** Yes, properly. SPDX headers via
`scripts/annotate.sh` (canonical from repo-foundation, synced
to babble). REUSE lint clean as a CI requirement.

## Tap distribution

Babble has been distributed as a `git clone` of toobuntu/babble.
Refactor/modular kept the same approach — it was a
workspace-style repo, not a tap.

**Carries to W3?** No. Distribution becomes a Homebrew tap:
`brew tap toobuntu/babble && brew install babble`. The repo
gets renamed `toobuntu/babble → toobuntu/homebrew-babble` per
Homebrew's tap-naming convention.

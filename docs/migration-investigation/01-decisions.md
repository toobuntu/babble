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

**Carries to W3?** Yes, with namespace flattening. As an
external command, the entry point is the class
`Homebrew::Cmd::Babble < AbstractCommand`; substantive
components live in `Babble::*`. The split between
`BrewUpdate`, `BrewUpgrade`, `MasUpgrade`, `MacOSUpdate`,
`AppManager`, `BundleLauncher`, `Waiter`, plus the new
`Config::{Loader, Validator, Merger, Reorganizer}` quartet
and the new `TerminalDetector`, follows refactor/modular's
boundaries with the configuration concerns extracted to
their own namespace. The `MacUtils::*` and `MacOSInterface::*`
namespaces collapse into `Babble::*` — there's no good reason
to maintain sub-namespaces in a single-purpose external
command.

**Whether each is shaped as a class or a module** is a
separate question — see [Class-vs-module decomposition
pattern](#class-vs-module-decomposition-pattern) below.

## Class-vs-module decomposition pattern

The "Module decomposition" section above lists *which* logical
units exist; this section addresses *how* each is shaped — as
a class or as a module-with-module-functions.

### Pattern guidance

The two Ruby idioms differ in whether they encapsulate state:

**Classes for state-bearing components.** Use a class when the
component has fields that multiple methods read and modify
during a single run: configuration loaded from disk, lists of
running apps captured at one point and consumed later, retry
counters, cached lookups. State lives in `@instance_variables`;
dependencies arrive via the constructor; multiple instances
are possible (useful for testing).

**Modules for pure utilities.** Use a module-with-`module_function`
or `class << self` block when each method takes its inputs as
arguments and returns its outputs without reading or mutating
shared state. Shell-out helpers, retry-with-backoff,
prefix-the-message helpers, env-file loaders.

### Reasoning

This is what Homebrew's own code does. Inspecting the active
codebase:

- `Homebrew::Cmd::Upgrade < AbstractCommand` — class (entry
  point with parsed args + `run` method)
- `Homebrew::Cleanup` — class with `attr_reader`, `initialize`
  (state-bearing)
- `Homebrew::Reinstall` — module with `module_function`
- `Cask::Caskroom` — module with module methods
- `Formula.installed` — class method on the Formula class

Pattern: classes for stateful domain objects, modules for
pure utilities, single-instance entry-point classes extending
`AbstractCommand`.

The pre-refactor archive at `stash/pre-refactor/lib/` got
this right for the components there: `class AppManager`
initialized from `@config_files`, `class ConfigManager`
similarly. Multiple methods sharing state across a run —
class is correct.

Refactor/modular's all-modules approach is uneven on this
question. Some modules are pure utilities (`MasUpgrade`'s
parsing, `DarkMode.enabled?`) — module is correct. Others
have state that they hide in `class << self` blocks plus
`@class_variables` (`BrewUpgrade` carries running-apps
snapshots, the upgrade list, retry counters at module level).
That hybrid is the worst of both worlds: it feels like a
class but loses encapsulation, makes testing harder, and
prevents multiple parallel instances.

W3 chooses explicitly per component.

### W3 component classification

**Classes (state-bearing):**

- `Homebrew::Cmd::Babble < AbstractCommand` — entry point;
  parsed CLI args + `run` method per Homebrew's external
  command idiom
- `Babble::Config::{Loader, Validator, Merger, Reorganizer}` —
  each holds its slice of state (loaded files, validation
  results, merged config, reorganized output)
- `Babble::Config` — top-level façade holding the merged
  validated config; exposes `#valid?`, `#errors`, `#warnings`,
  `#conflicts`, `#homebrew_entries`, `#mas_entries`
- `Babble::AppManager` — holds `@config` reference + cached
  running-app snapshots; methods orchestrate quit/reopen
  across the upgrade lifecycle
- `Babble::BrewUpdate`, `BrewUpgrade`, `MasUpgrade`,
  `MacOSUpdate` — each phase is a class taking
  `(app_manager:, config:)` in the constructor and exposing
  `#run`. Phase-local state (which casks are outdated, which
  apps need reopening, retry counters) lives in instance vars.

**Modules (pure utilities):**

- `Babble::Sh` — shell-out wrappers (or use Homebrew's
  `SystemCommand::Mixin` directly)
- `Babble::Retry` — retry-with-backoff helper
  (`Babble::Retry.with_retry { ... }`)
- `Babble::Env` — env-file loader; mutates `ENV` but doesn't
  carry state across calls
- `Babble::TerminalDetector` — one-shot detection
  (`Babble::TerminalDetector.host_terminal_casks`)
- `Babble::DarkMode` — `Babble::DarkMode.enabled?`
- `Babble::Formatter` — prefix-the-message helpers, if any
  beyond what Homebrew's `oh1`/`ohai`/`opoo`/`ofail` provide

### Entry point shape

```ruby
# cmd/babble.rb (Homebrew external command)
require "abstract_command"

module Homebrew
  module Cmd
    class Babble < AbstractCommand
      cmd_args do
        description <<~EOS
          An upgrade routine for Homebrew, Mac App Store, and macOS.
        EOS

        switch "--no-update",
               description: "Skip the brew update phase."
        switch "--always-descriptions",
               description: "Force descriptions for new formulae and casks."
        # ...
      end

      sig { override.void }
      def run
        Babble::Env.load_default_locations

        config = Babble::Config.load
        config.report_warnings_and_conflicts!

        app_manager = Babble::AppManager.new(config: config)

        Babble::BrewUpdate.new(app_manager: app_manager, args: args).run
        Babble::BrewUpgrade.new(app_manager: app_manager, config: config, args: args).run
        Babble::MasUpgrade.new(app_manager: app_manager, args: args).run
        Babble::MacOSUpdate.new(args: args).run
      end
    end
  end
end
```

### Phase class shape

```ruby
# cmd/babble/brew_upgrade.rb
module Babble
  class BrewUpgrade
    sig {
      params(app_manager: AppManager, config: Config, args: T.untyped).void
    }
    def initialize(app_manager:, config:, args:)
      @app_manager = app_manager
      @config = config
      @args = args
      @outdated_casks = T.let([], T::Array[String])
      @running_at_start = T.let(nil, T.nilable(T::Array[String]))
    end

    sig { void }
    def run
      list_outdated
      capture_running_apps
      quit_apps_for_outdated_casks
      run_upgrade
      reopen_quit_apps
    end

    private

    sig { void }
    def list_outdated
      # ... populates @outdated_casks
    end

    sig { void }
    def capture_running_apps
      @running_at_start = @app_manager.running_bundle_ids
    end

    # ... etc
  end
end
```

### Module shape (pure utility)

```ruby
# cmd/babble/retry.rb
module Babble
  module Retry
    class << self
      sig do
        type_parameters(:T)
          .params(
            max:     Integer,
            on_fail: T.proc.params(attempt: Integer).void,
            block:   T.proc.returns(T.type_parameter(:T)),
          )
          .returns(T.nilable(T.type_parameter(:T)))
      end
      def with_retry(max: 10, on_fail: ->(_n) {}, &block)
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
end
```

The body of the method takes its inputs as arguments and
returns its outputs. No state across calls. Module is
correct.

### Why not `module_function` everywhere?

`module_function` makes methods callable as both module
methods and instance methods (via `include`). For a single-
purpose external command like babble, no caller is going to
`include Babble::Retry` to get `with_retry` as an instance
method. The `class << self` form is more explicit and equally
ergonomic.

`module_function` is appropriate when the pattern of "include
me for a mixin" is genuinely useful (e.g., `Homebrew::Reinstall`
gets included by `Cmd::Reinstall`). Babble doesn't have that
shape.

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

Lookup order, two tiers (user and system) with user winning
by default:

1. **Process environment** (set by user shell, CLI prefix, or
   parent process) — always wins; no file load can override
2. **User**:
   `${XDG_CONFIG_HOME:-$HOME/.config}/babble/babble.env`
3. **System**: `/etc/babble/babble.env`

**Default precedence**: process env > user > system. Loading
order achieves this via `ENV[key] ||= value` (set only if not
already set): user loads first, system fills in remaining gaps,
process env was already in place before either file load.

**Sysadmin override**: setting
`BABBLE_SYSTEM_ENV_TAKES_PRIORITY` to any non-empty value in
the process environment inverts the file precedence: system
> user. `1` is the idiomatic example value, but any
non-empty value enables it — this mirrors Homebrew's
upstream env-var convention (per `man brew`: "environment
variables must have a value set to be detected… run
`export HOMEBREW_NO_INSECURE_REDIRECT=1` rather than just
`export HOMEBREW_NO_INSECURE_REDIRECT`"; the `=1` is
illustrative, not a contract). Useful for corporate-managed
macOS fleets where IT enforces /etc-defined defaults that
user-set values can't override. Independent of Homebrew's
`HOMEBREW_SYSTEM_ENV_TAKES_PRIORITY`; the two variables are
deliberately not coupled (babble and Homebrew are separate
entities; sysadmins who want both behaviors should set both
flags explicitly).

The `BABBLE_SYSTEM_ENV_TAKES_PRIORITY` flag itself must be
set in the process environment to take effect — setting it in
`babble.env` would create a chicken-and-egg situation since
the flag controls how `babble.env` is loaded. Document this
constraint in the user-facing docs.

**Why no prefix tier?** Homebrew's `brew.env` has a third
tier at `${HOMEBREW_PREFIX}/etc/homebrew/brew.env` because
Homebrew itself lives at HOMEBREW_PREFIX; per-prefix Homebrew
config is meaningful when a machine has multiple Homebrew
installations (Apple Silicon `/opt/homebrew` plus Rosetta
`/usr/local`). Babble is an external command tap inside
Homebrew — the tap directory is at
`${HOMEBREW_PREFIX}/Library/Taps/toobuntu/homebrew-babble/`,
not `${HOMEBREW_PREFIX}/etc/babble/`. Babble's behavior
shouldn't differ per Homebrew prefix; user preferences travel
with the user, not with the install location. The prefix tier
doesn't carry the same conceptual weight for babble that it
does for Homebrew, so it's omitted.

No upward directory walk for `babble.env` either — these are
user/host preferences, not per-project settings.

**Format**: line-based `KEY=VALUE` pairs. The parser is pure
Ruby (`Babble::Env.load_file`) — no shell sourcing.

Semantics, mirroring Homebrew's `bin/brew`
`export_homebrew_env_file`:

- One pair per line, matched by the anchored regex
  `\A([A-Z][A-Z0-9_]*)=(.*)\z`
- Lines that don't match (comments, blank lines, malformed)
  are silently skipped
- Filter to `BABBLE_*` prefix only — other variables are
  ignored
- Value is everything after the first `=`, taken **literally**:
  no shell expansion (`$VAR` stays as `$VAR`), no command
  substitution (`$(...)` stays as `$(...)`), no quote
  stripping (`"value"` stays as `"value"` with the quotes)
- Process environment wins: the parser uses
  `ENV[key] ||= value`, so an already-set value is preserved.
  CLI invocations can prefix the variable
  (`BABBLE_QUIET=1 brew babble`) and that takes priority over
  the file.

The pure-Ruby parser is mandated by the external command
shape: Homebrew sources its own `brew.env` in `bin/brew`
(bash) before the external command's Ruby runs. Babble can't
insert a pre-Ruby bash step; the parser must run inside Ruby.

```ruby
module Babble
  module Env
    KEY_PATTERN = /\A([A-Z][A-Z0-9_]*)=(.*)\z/

    class << self
      sig { params(path: T.any(String, Pathname)).void }
      def load_file(path)
        return unless File.readable?(path)
        File.foreach(path) do |line|
          next unless (m = KEY_PATTERN.match(line.chomp))
          key, value = m[1], m[2]
          next unless key.start_with?("BABBLE_")
          ENV[key] ||= value
        end
      end

      sig { void }
      def load_default_locations
        xdg_home = ENV["XDG_CONFIG_HOME"] || File.join(ENV.fetch("HOME"), ".config")
        user_path   = File.join(xdg_home, "babble", "babble.env")
        system_path = "/etc/babble/babble.env"

        # Each call uses ENV[key] ||= value (set only if not
        # already set), so the first load to provide a value
        # wins. The process env (set before babble runs) is
        # already in ENV and pre-empts every file load.
        if system_takes_priority?
          # Sysadmin override: load system first so its values
          # stick, then user fills in remaining gaps.
          load_file(system_path)
          load_file(user_path)
        else
          # Default: load user first so user values stick,
          # then system fills in remaining gaps.
          load_file(user_path)
          load_file(system_path)
        end
      end

      private

      # Mirrors Homebrew's upstream env-var convention: any
      # non-empty value enables the flag. `1` is the idiomatic
      # example, not the only accepted value. Per `man brew`,
      # the variable need only be "set to be detected".
      sig { returns(T::Boolean) }
      def system_takes_priority?
        value = ENV["BABBLE_SYSTEM_ENV_TAKES_PRIORITY"]
        !value.nil? && !value.empty?
      end
    end
  end
end
```

Called from `Homebrew::Cmd::Babble#run` before any other
phase orchestration starts.

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

**Carries to W3?** Auto-compile pattern wins, with
source-hash verification and user-visible transparency on
first compile. See
[`adrs/0001-swift-quit-alert-build-strategy.md`](adrs/0001-swift-quit-alert-build-strategy.md)
for the full ADR, including the Safety and transparency
design section that covers: SHA256 sidecar committed
alongside the source (`quit_alert.swift.sha256`), CI
enforcement of the sidecar via
`shasum -a 256 -c`, runtime verification in
`Babble::QuitAlertCompiler` with hard-fail on hash
mismatch, `ohai` messages on first compile printing source
path / target path / command / verified hash, and cache
key derivation that auto-invalidates when the source
changes. Refactor/modular's pre-compile approach is
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
`~/Library/Caches/Homebrew/bootsnap`. Added in commit 569b4e0
in response to
[Homebrew/brew discussion #5226](https://github.com/orgs/Homebrew/discussions/5226)
about transient bootsnap-cache corruption (the
`cannot load such file -- json/pure (LoadError)` failure mode).

Upstream may have addressed the original cause:
- [Homebrew/brew#16977](https://github.com/Homebrew/brew/pull/16977)
  (31 Mar 2024): "cleanup: fix various cases where cache wasn't
  being removed properly"
- [Homebrew/brew#18240](https://github.com/Homebrew/brew/pull/18240)
  (4 Sep 2024): "Invalidate Bootsnap cache on Gemfile.lock
  changes"
- [Homebrew/brew#18246](https://github.com/Homebrew/brew/pull/18246)
  (4 Sep 2024): "startup/bootsnap: base key on in install state
  rather than projection"

Whether bootsnap-specific corruption still surfaces in current
Homebrew is open. The retry mechanism is **kept regardless**:
it's general defense against any transient `brew upgrade`
failure (network blips, intermittent rate limits, partial
downloads), not just bootsnap. The bootsnap-cleanup hook is
harmless if the cache isn't corrupt — clearing a healthy cache
costs a few seconds of cache rebuild on the next brew launch,
no correctness impact.

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

**Carries to W3?** Yes, with active enforcement.

**Discipline:**

- **Every file is `# typed: strict`** unless there's a
  documented reason otherwise (rare; only for files that
  must accept genuinely dynamic input from a non-typed
  boundary).
- **Every method has a `sig`**, including private helpers.
  At `typed: strict`, Sorbet enforces this.
- **`void` only when justified**: methods that genuinely
  return nothing meaningful. `initialize` (Ruby convention),
  `run` entry points on phase classes, and pure side-effect
  methods that mutate state. Methods with a meaningful return
  value get the proper return type, never `void`.
- **`T.untyped` only where unavoidable**: e.g., the `args`
  object from Homebrew's `cmd_args do ... end` builder is
  intrinsically dynamic. Everywhere else, prefer specific
  types: `T::Array[String]`, `T::Hash[String, Integer]`,
  `T.nilable(String)`, `T::Boolean`, etc.
- **Type parameters for generic helpers**: `Babble::Retry.with_retry`
  uses `type_parameters(:T)` so the block's return type
  flows through.
- **CI enforcement**: `brew typecheck` (which runs
  `srb tc`) is a required CI status check. Failures block
  merge.
- **Local enforcement**: maintainer runs `brew style` plus
  `brew typecheck` before each commit. The pre-commit hook
  (synced from repo-foundation) runs the same.

Example of strict typing in practice:

```ruby
# typed: strict
# frozen_string_literal: true

require "abstract_command"
require "sorbet-runtime"

module Babble
  class BrewUpgrade
    extend T::Sig

    sig { params(app_manager: AppManager, config: Config, args: T.untyped).void }
    def initialize(app_manager:, config:, args:)
      @app_manager = app_manager
      @config = config
      @args = args
      @outdated_casks = T.let([], T::Array[String])
      @running_at_start = T.let(nil, T.nilable(T::Array[String]))
    end

    sig { void }
    def run
      list_outdated
      capture_running_apps
      quit_apps_for_outdated_casks
      run_upgrade
      reopen_quit_apps
    end

    sig { returns(T::Array[String]) }
    def outdated_casks = T.must(@outdated_casks)

    private

    sig { void }
    def list_outdated
      output = Utils.safe_popen_read(HOMEBREW_BREW_FILE, "outdated", "--cask", "--json=v2")
      data = T.let(JSON.parse(output), T::Hash[String, T.untyped])
      @outdated_casks = T.cast(
        data.fetch("casks", []).map { |c| T.cast(c.fetch("name"), String) },
        T::Array[String],
      )
    end

    sig { void }
    def capture_running_apps
      @running_at_start = @app_manager.running_bundle_ids
    end

    sig { params(bundle_id: String).returns(T::Boolean) }
    def app_was_running?(bundle_id)
      T.must(@running_at_start).include?(bundle_id)
    end
  end
end
```

The pseudocode in the
[Class-vs-module decomposition pattern](#class-vs-module-decomposition-pattern)
section above shows mostly `void` methods because that's what
the entry-point + run + state-mutation pattern produces.
Helper methods, query methods, and computation methods get
proper return types as shown here.

## Testing discipline

RSpec, with coverage for every component.

**Discipline:**

- **Per-component spec files** mirror the source layout:
  `cmd/babble/brew_upgrade.rb` → `spec/babble/brew_upgrade_spec.rb`
- **Public API gets coverage first**: every public method on
  every class/module has at least one spec example
- **Edge cases get explicit specs**: empty inputs, nil
  returns, Unicode bundle IDs, casks with no description,
  fonts (which intentionally have `desc nil`), etc.
- **External boundaries are mocked**:
  - `safe_system HOMEBREW_BREW_FILE, ...` mocked to return
    canned output
  - JXA quit calls mocked
  - File system reads against fixture YAML files in
    `spec/fixtures/`
  - Process detection (`ps`, `lsappinfo`) mocked
- **Integration boundary stays small**: a few spec examples
  exercise the full phase orchestration end-to-end with
  mocked boundaries; most specs are unit-level
- **CI enforcement**: `brew tests` runs the spec suite as a
  required check

The validation tests already in refactor/modular's
`BrewUpgrade.test_valid_*` methods (not real specs; just
method-level sanity checks the maintainer ran manually) become
proper spec examples in W3. They're a starting point, not the
final coverage.

Reference: Homebrew's own spec structure at
`Library/Homebrew/test/` is the model. Each `cmd/foo.rb` has
a corresponding `test/cmd/foo_spec.rb`. Use the same layout.

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

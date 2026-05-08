<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# PR #1 review — Rewrite babble as modular Ruby application

This is an internal review document, written for the sole maintainer. The
voice is direct: blockers are blockers, suggestions are suggestions, and
positives are noted but not dwelt on. Code citations are line-or-snippet
oriented; refer to the working tree at `../babble-pr1/` for full context.

## Top-line verdict

The PR delivers what its description claims at the structural level: a Ruby
orchestrator with a Bash wrapper, a YAML-driven config, a Swift quit alert,
and module separation between brew, mas, macOS, app lifecycle, and prompts.
That said, **the PR cannot ship as written.** A non-trivial number of the
ported behaviors are functionally broken — most consequentially, the GUI
app detection has never matched a single bundle ID — and several behavioral
regressions vs. the ksh original would surprise anyone running babble for
the first time after the upgrade. The right response is to **keep the
architecture, redo the implementation in a follow-up branch, and treat the
current commits as a structural sketch** rather than as a code-complete
draft. The list below is what to fix; the path-forward section at the
bottom suggests how.

This review is organized as: blockers (must fix before merge), substantive
issues (should fix; deferred is acceptable but tracked), nits (mention,
move on), and what's done well.

---

## Blockers

### B1. `running_bundle_ids` returns an empty array on every macOS

In `lib/babble/app_manager.rb`, the running-app detection uses the wrong
key:

```ruby
def running_bundle_ids
  stdout, stderr, status = Open3.capture3("lsappinfo", "list")
  # ...
  bundle_ids = []
  stdout.each_line do |line|
    if line =~ /"CFBundleIdentifier"="([^"]+)"/
      bundle_ids << Regexp.last_match(1)
    end
  end
  bundle_ids.uniq
end
```

`lsappinfo list` does not emit `CFBundleIdentifier="..."` — that's an
`Info.plist` key, not an `lsappinfo` field. The actual output uses
`bundleID="..."`, which is why the original ksh used the awk pattern
`/bundleID/ {print $NF}` and the prototype `RunningGUIBundleIDs` class used
`/^\s*bundleID="(.+?)"/`. As a result, this method **always returns an
empty list**. The downstream consequence is that `BrewUpgrade#run` and
`MasUpgrade#run` both compute `apps_to_manage = []` — *no apps are ever
quit*, no quit confirmation dialogs are shown, and no apps are ever
reopened. The entire app-lifecycle feature set is silently disabled.

This is one regex character away from working, but it's hard to overstate
how serious "it never matched anything in any test" is for a feature that
is the headline of the PR description. It also strongly implies the
end-to-end flow has never been exercised on a real machine. Fix: replace
with the prototype's working pattern (`/^\s*bundleID="(.+?)"/`), and add an
integration spec that stubs `lsappinfo list` with a recorded fixture and
asserts at least one bundle ID is parsed.

### B2. `lsregister -dump` invoked on a per-poll, per-bundle basis

`bundle_launcher.rb` has two paths that call `lsregister -dump`:
`app_registered?` (used as the polling predicate in `wait_until_reopened`)
and `app_path_via_lsregister_dump` (used as the mdfind fallback). On
macOS, `lsregister -dump` is a ~20-second operation in steady state and
slower under load, because it serializes the entire Launch Services
database. The cask-tools `purge-quarantine` implementation caches its
dump at `HOMEBREW_CACHE/purge-quarantine/lsregister.dump` for 5 minutes
precisely because of this cost.

In babble's `wait_until_reopened`:

```ruby
def wait_until_reopened(bundle_id, timeout)
  Timeout.timeout(timeout) do
    loop do
      break if app_registered?(bundle_id)
      sleep 0.2
    end
  end
end
```

With a 10 s timeout and 0.2 s polling, `app_registered?` will be invoked
up to 50 times before timing out — and each invocation can take 20 s on
its own. Reopening five apps after a brew upgrade therefore can hang for
many minutes per app and tens of minutes overall. This implementation
cannot have been tested on any real macOS install.

Fix: use a cheap registration check instead. `osascript -e 'id of app
"<bundle-id>"'` returns the bundle ID itself if the app is registered (or
errors with a known message if not), in tens of milliseconds. Or use
`mdfind "kMDItemCFBundleIdentifier == '<bundle-id>'"`, which is also
fast. Reserve the `lsregister -dump` call for the cold path
(`app_path_via_lsregister_dump`) and cache it for the duration of a
single babble run.

### B3. `brew outdated` invoked without `--greedy-auto-updates --fetch-HEAD`

The detection-side calls in `brew_upgrade.rb`:

```ruby
def display_outdated_packages
  stdout, _, status = Open3.capture3("brew", "outdated", "--json=v2")
  # ...
end

def outdated_casks_json
  stdout, _, status = Open3.capture3("brew", "outdated", "--cask", "--json=v2")
  # ...
end
```

…but the upgrade-side call adds the flags:

```ruby
def upgrade_packages
  success = system(
    "brew", "upgrade",
    "--greedy-auto-updates",
    "--fetch-HEAD",
    "--display-times"
  )
end
```

Most casks Homebrew tracks have `auto_updates true` set on the cask
definition, which means `brew outdated` ignores them by default. The
original ksh always passed `--greedy-auto-updates --fetch-HEAD --verbose`.
The mismatch here means the "outdated" report can be empty while
`brew upgrade --greedy-auto-updates` would actually do meaningful work —
or worse, the quit-before-upgrade list misses casks that the upgrade step
then quits implicitly via `uninstall quit:` stanzas. Detection and
execution must use the same flags.

Fix: pass the same flags to all four `brew outdated` invocations
(formulae, casks, JSON, verbose). Centralize via a constant
`BREW_OUTDATED_ARGS = %w[--greedy-auto-updates --fetch-HEAD]`.

### B4. The unsafe-to-quit cancel button kills the entire babble run

In `brew_upgrade.rb#quit_apps`:

```ruby
if entry["unsafe_to_quit"]
  success = AppManager.quit_with_confirmation(bundle_id, app_name)
  exit(1) unless success
else
  # ...
end
```

`AppManager.quit_with_confirmation` returns `false` when the user clicks
Cancel on the Swift dialog. The current code interprets that as a fatal
error and `exit(1)`s the orchestrator. This is a UX regression: the user
is being asked "do you want to quit Chrome before upgrading it?" — clicking
"Cancel" should mean "skip Chrome's upgrade" or "keep Chrome running and
let me decide what to do," not "abort all of babble including the
unrelated mas and macOS upgrades I queued."

Two acceptable behaviors:

1. **Skip just this cask.** Remove the cask from `apps_to_manage` and
   continue. `brew upgrade` will still try to upgrade Chrome, which will
   fail or leave the running app on the old version — but the rest of the
   workflow proceeds.
2. **Skip this cask and exclude it from the upgrade list.** Compute the
   outdated tokens, drop the user-vetoed ones, and pass the surviving
   list to `brew upgrade --cask token1 token2 …`. This is what PR #3 was
   reaching for.

Option 2 is the right answer; B6 below requires the same machinery.

### B5. `update_if_needed` silently skips `brew update`

```ruby
def update_if_needed
  last_update_file = File.join(CACHE_DIR, "last_brew_update")
  if !File.exist?(last_update_file) || (Time.now - File.mtime(last_update_file)) > 3600
    puts "Updating Homebrew..."
    system("brew", "update")
    FileUtils.mkdir_p(File.dirname(last_update_file))
    FileUtils.touch(last_update_file)
  end
end
```

The user pressed "Run command" expecting `brew update` to run. On the
second run within an hour, this method silently does nothing — no output,
no skip message, no indication that the command was elided. The ksh
original always runs `brew update`, which is the documented behavior of
the tool ("Updating Homebrew -- The Missing Package Manager for macOS…").
Also: `system("brew", "update")` discards the exit status and the
touch-file is created regardless of whether the update succeeded.

Fix: drop the staleness gate entirely. If the user wants to skip
`brew update`, they can set `HOMEBREW_NO_AUTO_UPDATE=1` for the run.
Alternately, keep the gate but emit a one-line "skipping `brew update`;
metadata is $age old" message and check the exit status.

### B6. The terminal-running-babble issue is unaddressed

The README's "to do" list has carried the line "Do not attempt to upgrade
the terminal being used to run Babble itself" since v0.5.0. PR #3 was
intended to address it. Neither PR #1 nor PR #3-on-disk does. Since PR #3
is being discarded (see `pr3-review.md`), the terminal exclusion belongs
in the post-PR-#1 cleanup, and the architecture must accommodate it. The
mechanism is straightforward: enumerate the outdated casks as a Ruby
array, drop the running terminal's token, then call `brew upgrade --cask
<surviving-tokens>`. Filtering by an explicit list also enables B4
option 2.

### B7. `quarantine_purger.rb` should not exist

The repository `homebrew-cask-tools` already ships `brew purge-quarantine`,
a battle-tested external command with a seven-tier bundle discovery
strategy, real test coverage, idiomatic Homebrew internals
(`SystemCommand::Mixin`, `CaskLoader`, `lsregister` caching, BOM/`pkgutil`
fallbacks, `mdfind` last-resort), and proper tap distribution.
`quarantine_purger.rb` is a port of the rough prototype: single tier
(Caskroom glob), no tests, broken in places (see N1 below), and uses
`Find.find` to traverse the entire cask subtree which is much slower than
`Dir.glob`. There is no reason to maintain a parallel, inferior
implementation in babble.

Fix: delete `lib/babble/quarantine_purger.rb`. Add a probe at startup that
checks whether `brew purge-quarantine` is installed (e.g. by searching
`brew commands --quiet` for the name), and call it per outdated cask if
present. If not present, emit a single hint line — `babble: Tip:
brew tap toobuntu/cask-tools && brew install … to enable quarantine
removal on upgraded casks.` — and skip the step entirely. The babble
README should mention `brew purge-quarantine` as a recommended companion
tool. Bug fixes flow into one place; babble keeps its scope narrow.

### B8. No tests, no Sorbet check, no REUSE compliance

The PR claims `# typed: strict` throughout but ships no `Gemfile`, no
`sorbet/` directory, no `srb tc` invocation in CI. The magic comment alone
does nothing. Likewise, it ships no test suite at all. CI only runs
`script/style` and `script/syntax` — and the latter only checks Ruby with
`ruby -c` (parse-only).

Per the agreed-on conventions for this and sister repos
(`homebrew-cask-tools`, `blackoutd`), the migration must include:

- A `Gemfile` and `Gemfile.lock` with `sorbet`, `sorbet-runtime`, `rspec`,
  `rubocop`, and the Homebrew rubocop config.
- `sorbet/config` and `sorbet/rbi/` after `srb init`.
- `spec/` with `spec_helper.rb` and at least smoke specs per module.
- `.rspec`, `.rubocop.yml` (or whatever config inheritance from
  homebrew-cask-tools makes sense).
- REUSE/SPDX headers via `scripts/annotate.sh`. The PR has no SPDX headers
  anywhere; `LICENSE` alone doesn't satisfy REUSE.
- CI on `macos-14` (or newer) for RSpec runs that need real `lsappinfo`,
  `osascript`, `defaults`, and `softwareupdate`. CI on Ubuntu can keep
  doing style/syntax/Sorbet, but RSpec needs macOS runners.

This is significant work and is the largest single chunk of post-merge
cleanup, but it's table-stakes for shipping. See `tech-debt.md` items in
the P0 band for breakdown.

### B9. `IMPLEMENTATION_SUMMARY.md` is committed at the repo root

This is PR-description text, not project documentation. It will go stale
the moment the next change lands and there is no story for keeping it
synchronized. Either move its useful contents into the README and the
`docs/` tree (architecture overview belongs in `docs/architecture.md`),
into a `CHANGELOG.md`, or delete it. The pattern in the sister repos is
to keep the PR description in the PR conversation, not in the tree.

---

## Substantive issues (should fix; tracked if deferred)

### S1. `bin/babble` portable-Ruby setup is overcomplicated and fragile

The wrapper sources `${HOMEBREW_LIBRARY}/Homebrew/utils/ruby.sh` and calls
`setup-ruby-path`. That function is internal Homebrew shell, not API; it
can change shape across `brew` versions, and it can `exit 1` under
conditions Homebrew's outer code recovers from but our `set -euo pipefail`
will not. The simpler approach Homebrew's own actions use is:

```bash
HOMEBREW_RUBY_PATH="$(brew --repository)/Library/Homebrew/vendor/portable-ruby/current/bin/ruby"
if [[ ! -x "$HOMEBREW_RUBY_PATH" ]]; then
  brew vendor-install ruby
fi
exec "$HOMEBREW_RUBY_PATH" -W1 "$ruby_cli" "$@"
```

This sidesteps the `setup-ruby.sh` machinery, avoids any dependency on
`HOMEBREW_DEVELOPER` toggling Bundler installs, and produces clearer error
messages when something is genuinely wrong. The only thing the wrapper
still needs to do beyond that is load the `brew.env` files (which it
already does correctly).

There is also a small bug in the existing wrapper:
`${HOMEBREW_RUBY_DISABLE_OPTIONS}` is unset on a fresh install, so the
`exec` line passes an empty positional that Ruby interprets as a script
name. Either guard it (`${HOMEBREW_RUBY_DISABLE_OPTIONS:+...}`) or drop
it; the simplified path above doesn't need it.

### S2. Token-to-display-name mangling

`brew_upgrade.rb#quit_apps` derives the user-facing app name from the
cask token:

```ruby
app_name = entry["token"].split("-").map(&:capitalize).join(" ")
```

`coteditor` becomes "Coteditor" (should be "CotEditor"). `iterm2` becomes
"Iterm2". `vscodium` becomes "Vscodium". `protonvpn` becomes "Protonvpn"
(should be "Proton VPN"). The unsafe-to-quit Swift dialog will display
these mangled names to the user, in a confirmation dialog, immediately
before quitting their app.

The right source is `lsappinfo info -only name "<bundle-id>"`, which
returns the actual display name as macOS knows it. Cache the results in
a hash keyed by bundle ID to avoid repeated lookups. Fall back to the
mangled token only if the lookup fails.

### S3. Mac App Store: migrate to mas v7 JSON output

`mas_upgrade.rb` parses the human-readable output of `mas outdated`:

```ruby
stdout.split("\n").map do |line|
  line.split.first.to_i
end
```

`mas` v7.0 (released earlier this year) added structured JSON output to
`list`, `outdated`, `search`, `lookup`/`info`, and `config`. Migrating to
`mas outdated --json` removes a layer of fragile string parsing and gives
us proper access to `bundleID`, `displayName`, `version`, etc. without
needing the user to maintain the `name` and `bundle_ids` fields in
`config/apps.yml` — those can come from `mas list --json <app_id>` at
runtime. Detect mas version via `mas version` (or just probe `mas list
--json` and fall back to text parsing if it errors out).

### S4. Retry-on-failure loop missing

The ksh original wraps `brew upgrade` in a `repeat_command` loop with up
to 10 attempts, where the fallback between attempts is to clear
`~/Library/Caches/Homebrew/bootsnap`. This was added in response to
[Homebrew/brew discussion #5226](https://github.com/orgs/Homebrew/discussions/5226)
about transient bootsnap-cache corruption. The Ruby version doesn't have
this. Brew upgrade failures are not so rare that this should be dropped;
the retry loop is one of the few features babble adds beyond raw
sequencing. Port the loop to a small helper:

```ruby
module Babble::Retry
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
```

### S5. Config required at startup; should default to empty

`Babble::CLI.run` exits 1 if `config/apps.yml` doesn't exist:

```ruby
unless config_file && File.exist?(config_file)
  $stderr.puts "Error: Configuration file not found at #{config_file}"
  $stderr.puts "Please create config/apps.yml in the babble installation directory"
  exit 1
end
```

The ksh original needs no config and works out of the box. A Ruby babble
should match: a missing config file means "no apps to quit-and-restart,"
and the upgrade flow should still proceed. The example `config/apps.yml`
should ship as `config/apps.example.yml` and be gitignored as
`config/apps.yml` — see also S6 below on config location.

### S6. Config location should follow Homebrew's lookup order

The PR ships a real config at `config/apps.yml` inside the repo. That
isn't the user's data — it's whatever the maintainer happened to commit.
Adopt the Homebrew-style lookup order, first-match wins:

1. `$BABBLE_CONFIG` (env override)
2. `./.babblefile.yml` (current directory)
3. `<repo-root>/.babblefile.yml` (project root)
4. `${XDG_CONFIG_HOME:-$HOME/.config}/babble/apps.yml`
5. `$HOME/.babblefile.yml` (legacy/discoverable)
6. `/etc/babble/apps.yml`

The repo ships `config/apps.example.yml` as documentation and adds
`/config/apps.yml` to `.gitignore`. The maintainer's existing
`config/apps.yml` content (which currently has `pikachuexe-freetube`,
several specific tokens, etc.) belongs in `~/.config/babble/apps.yml` on
the maintainer's machine, not in the public repo.

### S7. Per-bundle 0.5 s sleep slows quit phase unnecessarily

```ruby
entry["bundle_ids"].each do |bundle_id|
  # ... quit_app ...
  sleep 0.5
end
```

For an app like `adobe-acrobat-reader` with three bundle IDs, that's 1.5 s
of dead time per app. Multiply across a typical Saturday-morning upgrade
run with five outdated casks and you're spending 7+ seconds doing nothing.
The reason to sleep is to let `app.quit()` propagate before checking
again, but we don't check again — we just move on. Either drop the sleep
entirely, or replace it with a poll
(`until !app_running?(bundle_id) || timeout`).

### S8. `quit_with_confirmation` exit-code semantics duplicated

The Swift binary returns 0 / 1 / 2 / 3 with documented meanings, and
`AppManager#quit_with_confirmation` then uses a `case` statement to
translate those into truthy/falsy and stderr messages. This is a
serviceable shape, but if `quit_alert` ever grows a fourth exit code (e.g.
"timeout") the consumer has to be updated separately. Consider returning
a structured result (`{:approved, :cancelled, :icon_error, :usage_error,
:unknown}`) from a small parser function, and let the call site decide
what each means. Lower priority.

### S9. Swift quit_alert: icons embedded as base64 in source

`swift/src/quit_alert.swift` embeds two ~2 KB base64-encoded SVG strings
directly in the source. The repo also ships
`assets/refresh-dot-{light,dark}.svg`. Either pass the icon path as a
command-line argument to `quit_alert` (the older personal version did
this) so that asset updates don't require recompiling, or use Swift's
`#fileLiteral` / `Bundle.module` so the icon is referenced rather than
inlined. The base64 strategy works but is brittle: any asset update is a
recompile.

### S10. Auto-compile of Swift on first run: document the rationale

Auto-compile via `xcrun swiftc` at first use is the right call given the
Apple Developer cert situation (no signing → no Gatekeeper-clean
distribution → can't ship a pre-built binary in the repo). This is worth
recording as an Architecture Decision Record
(`docs/decisions/0001-swift-quit-alert-build-strategy.md`) so future
readers don't try to "improve" it by checking in a binary. The ADR should
state: rationale (no Apple Developer cert), tradeoffs (requires
xcode-command-line-tools at runtime; first run is slower; no
codesign/notarize), failure modes (no toolchain → fall back to `osascript
display dialog` or skip the prompt and go straight to quit), and the
trigger that would change the decision (acquiring an Apple Developer
cert, or moving to a notarized installer pipeline).

`AppManager.ensure_quit_alert_compiled` raises on `swiftc` failure, which
under the current call chain just propagates up and crashes babble. A
fallback path — "show an `osascript display dialog` with the same
question; if the user clicks Continue, proceed; otherwise skip this app"
— would make the feature degrade gracefully on machines without
xcode-command-line-tools.

### S11. ConfigManager validation logic duplicated for homebrew/mas

`config_manager.rb#validate_config` has two near-identical branches
(homebrew entries and mas entries) with the same shape of validation,
conflict detection, and bundle ID checking. The PR description claims
this *removes* duplication vs. the prototype. It does, somewhat — the
prototype had two separate modules each duplicating the validation. But
within `validate_config`, the logic is still copy-pasted. A small
`validate_entry(entry, kind:, key_name:)` helper would collapse the two.
Lower priority; ConfigManager works.

### S12. `ConfigManager.check_duplicates` defined but never called

```ruby
def check_duplicates(config_file)
  return unless yq_available?
  # ... reads token list via yq, reports duplicates ...
end
```

This method is defined but never invoked from
`load_and_validate_configuration` or anywhere else. Either wire it into
the validation pass (after the file loads, before the schema check) or
remove it.

### S13. `BrewUpgrade#display_outdated_packages` returns boolean by side effect

The method prints the outdated list and returns `true`/`false` to indicate
whether anything is outdated. The naming and side effects are tangled:
"display" suggests output-only; the boolean implies a query. Split into
`outdated_summary` (returns a struct of `{formulae:, casks:}`) and a
separate `print_outdated_summary(summary)`. Callers can branch on
`summary.empty?`. Lower priority but improves testability.

---

## Nits

### N1. `quarantine_purger.rb#app_candidates` uses Find.find

```ruby
def app_candidates(root)
  candidates = []
  Find.find(root) do |path|
    candidates << path if path.end_with?(".app")
  end
  candidates
end
```

This recurses the entire cask subdirectory. Adobe casks have hundreds of
files; this is slow, and most paths won't be `.app` bundles. The
prototype used `Dir.glob("#{base}/*/*.app", File::FNM_CASEFOLD)`, which
scans only the immediate version directory. Moot if `quarantine_purger`
is deleted (B7), but documented for completeness.

### N2. `brew_upgrade.rb` mixes `puts` and `$stderr.puts` inconsistently

Some progress messages go to stdout, some to stderr; some warnings go to
stderr, others to stdout. Standardize on a small logger module
(`Babble.info`, `Babble.warn`, `Babble.debug`) so all "what is babble
doing right now" lines land on stderr (separable from `brew`'s actual
output on stdout) and so a future `--quiet` flag has a single place to
hook.

### N3. `Open3.capture3` calls scattered across modules

A small `Babble::Sh` wrapper would centralize stderr/stdout handling,
exit-status checking, and the eventual `--debug` echo of every command.
Currently `BrewUpgrade`, `MasUpgrade`, `MacOSUpdate`, `AppManager`,
`BundleLauncher`, `QuarantinePurger`, and `ConfigManager` each re-roll
this. Low priority, but cleanup-as-you-go.

### N4. `script/style` and `script/syntax`: Ruby left out of style

`script/syntax` was extended to run `ruby -c` on `lib/babble/*.rb`, which
catches parse errors but not style. `script/style` only knows about Bash.
Add `rubocop` (or `brew style` if we adopt the Homebrew-style rubocop
inheritance) to `script/style`. Sorbet typecheck (`srb tc`) belongs there
too once the Sorbet setup lands.

### N5. `.gitignore` doesn't match the file actually shipped

The PR's `.gitignore` lists `.cache/` (which is the per-user cache, not
something that ever lives in this repo) but doesn't list
`config/apps.yml` (which is in the tree and contains user-specific app
configuration). Per S6, the user's config should never have been
committed.

### N6. `tput sgr0` and `tput setaf` calls retained from ksh in waiter.rb

The Ruby `Waiter` module hardcodes ANSI sequences inline (`"\e[33m"` etc.)
where the ksh original used `tput`. This is a pragmatic choice (Ruby has
no `tput` binding and shelling out per call is wasteful), and the values
are stable across all terminals babble would ever run on. Worth a comment
explaining the deliberate departure from the ksh version, but not a fix.

---

## What's done well

A short section to make sure we don't lose what's right by tearing down
what's wrong.

The module decomposition (`Orchestrator`, `BrewUpgrade`, `MasUpgrade`,
`MacOSUpdate`, `AppManager`, `BundleLauncher`, `ConfigManager`,
`QuarantinePurger`, `Waiter`, `CLI`) is the right shape — close to the
prototype's design intent, cleaner than the prototype's actual code, and
matches what we're going to want for testability. **Keep this.**

The `AppManager / BundleLauncher` split — quit-side in `AppManager`,
reopen-with-fallbacks in `BundleLauncher` — is also good. The fallback
chain (`open -b → launchctl asuser → lsregister force-register`) is the
right shape, even though the current implementation has the
`lsregister -dump` performance bug.

The bash entry point's `brew.env` loading is correct and faithful to
`bin/brew`'s behavior. The Ruby-finding portion needs to change (S1) but
the env-loading code is keepable.

Module-level `# typed: strict` and `# frozen_string_literal: true` are
both correct defaults; we just need the actual Sorbet enforcement to back
them up.

The Swift quit_alert as a separate compiled binary (rather than inline
osascript) is the right call for the icon-themed dialog, and the
exit-code interface is clean. Lots of small quality details here are
right (dark/light mode, NSAlert vs. dialog, button order matching macOS
conventions).

Killing the `restart_list_brew`/`restart_list_mas` arrays from the ksh in
favor of YAML is an unambiguous improvement.

---

## Recommended path forward

This PR's branch should not be force-merged as-is, and a one-shot "address
all comments" pass is unlikely to get there cleanly given the spread of
issues. My recommendation:

1. **Tag v0.5.2 from `main`** with the two-line `print` diff as-is. That
   discharges the small ksh-side debt and gives us a known-good fallback
   release while we work on Ruby.

2. **Cut a fresh branch** from `main` named `ruby-migration` (not
   `copilot/rewrite-babble-as-ruby-app`; we want to leave that one as a
   reference). Cherry-pick the parts of PR #1 that survive review:
   - The `bin/babble` wrapper *with the S1 simplification applied*
   - `lib/babble/{orchestrator,cli,waiter,constants,bundle_launcher}.rb`
   - `lib/babble/macos_update.rb`
   - `swift/src/quit_alert.swift` *with the S9 icon-path argument applied*
   - The shape of `lib/babble/{brew_upgrade,mas_upgrade,app_manager,config_manager}.rb`,
     but rewritten to fix the blockers

   Leave behind `IMPLEMENTATION_SUMMARY.md` and
   `lib/babble/quarantine_purger.rb`.

3. **Land the conventions stack in one early commit** before any code:
   `Gemfile`, `Gemfile.lock`, `.rubocop.yml`, `.rspec`, `sorbet/`,
   `LICENSES/`, `scripts/annotate.sh`, `.githooks/pre-commit`,
   `AGENTS.md`, `CLAUDE.md`, `docs/shared-guidelines.md`,
   `docs/agent-principles.md`, `docs/architecture.md`. This sets the
   ground rules for everything after. Reference homebrew-cask-tools and
   blackoutd for templates.

4. **Address blockers in dependency order**:
   B1 (regex) → B3/B4/B5 (semantics) → B2 (lsregister caching) → B7
   (delete quarantine_purger, add brew purge-quarantine probe) → B6
   (terminal exclusion) → B8 (test suite + Sorbet runtime + REUSE +
   macOS CI runner). Each gets its own commit; each gets its own RSpec.

5. **Then substantive issues** (S1–S13) in priority order. S1 (bash entry
   point), S3 (mas JSON migration), S4 (retry loop), S5/S6 (config
   resolution) before the others.

6. **Open the PR for merge** only after `script/style`, `srb tc`, `rspec`,
   and the macOS smoke run are green. The current PR description should
   be replaced with a brief summary; the laundry-list of changes from
   `IMPLEMENTATION_SUMMARY.md` doesn't carry through.

Estimated work: 2–3 focused sessions for the structural cleanup (blockers
+ conventions stack), then 3–4 more for the substantive issues, terminal
detection, and tests. Not trivial, but the architecture is sound enough
that we don't have to start from a blank file.

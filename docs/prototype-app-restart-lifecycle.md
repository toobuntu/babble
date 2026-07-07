<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Prototype for a macOS application manager

Given an application identifier, request a graceful quit via Apple Events, wait until LaunchServices no longer reports the application as registered, fail on timeout, then launch a new instance. This avoids racing LaunchServices teardown during application restart.

```shell
# Quit an app by its app name or bundle ID.
# Exits 0 unless the app name or bundle ID is unknown.
quit_app () {
  /usr/bin/osascript -l JavaScript - "$1" <<'EOF'
function run(argv) {
    const app = Application(argv[0]);

    if (app.running()) {
        app.quit();
    }
}
EOF
}
quit_app FreeTube
unset -f quit_app

# LaunchServices presence check
ls_presence() {
  /usr/bin/lsappinfo info \
        -only pid,isregistered \
        -app FreeTube |
       /usr/bin/grep -q .
}

# Wait for LS to clear (50 ticks x 0.1 s sleep = 5 s total, by design)
timeout=50
while [ "$timeout" -gt 0 ] && ls_presence; do
  sleep 0.1
  timeout=$((timeout - 1))
done
unset -v timeout

# Hard failure if still present
if ls_presence; then
  printf >&2 "%s\n" \
    "Timed out waiting for FreeTube to quit." \
    "Please quit it manually and then run:" \
    "  /usr/bin/open -a /Applications/FreeTube.app"
  exit 1
fi

unset -f ls_presence

# Open by bundle ID
/usr/bin/open -b io.freetubeapp.freetube
# Open by app name
# /usr/bin/open -a FreeTube
# Open by path to app bundle
# /usr/bin/open -a /Applications/FreeTube.app
```

The full lifecycle forces readiness to re-open deterministically, as Homebrew does in the `reopen_apps_after_upgrade` method in $(brew --repository)/Library/Homebrew/cask/upgrade.rb:

- quit → poll LS disappearance
- upgrade
- run lsregister -f <app>
- launch once with open -b

Something like:

```shell
# Launch an app by bundle ID.
# Exits 0 once LaunchServices can resolve and the app is running.
# May retry due to LaunchServices reindex lag after install/upgrade.

launch_app () {
  /usr/bin/open -b "$1"
}

# LaunchServices presence check (running state)
ls_running() {
  /usr/bin/lsappinfo info \
        -only pid,isregistered \
        -app "$1" |
    /usr/bin/grep -q .
}

# Wait for app to become visible to LaunchServices (50 x 0.1 s = 5 s)
timeout=50
while [ "$timeout" -gt 0 ]; do
  if ls_running "$1"; then
    break
  fi

  # retry launch because LS may not yet recognize bundle post-upgrade
  launch_app "$1"

  sleep 0.1
  timeout=$((timeout - 1))
done
unset -v timeout
unset -f launch_app

# Hard failure if LS never sees it
if ! ls_running "$1"; then
  printf >&2 "%s\n" \
    "Timed out waiting for app to reopen." \
    "Try opening it manually:" \
    "  /usr/bin/open -b ${1}"
  exit 1
fi

unset -f ls_running
```

## Homebrew's approach with quit and reopen

Casks which contain an uninstall: :quit directive are reopened by Homebrew. Homebrew is recording bundle IDs that should be restarted, attempting launch once system transitions are done, and retrying on failure to launch.

RUNNING
  → QUIT_REQUESTED
  → QUIT_CONFIRMED
  → UPGRADE_APPLIED
  → LS_REINDEX (artifact normalization, not app state)
  → RESTART_REQUESTED
  → LAUNCH_ATTEMPTED
  → RESTARTED

Homebrew just installed the app, so it knows its filesystem path and can invoke `/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f <path>` on it to avoid having to poll lsappinfo or re-attempt open -b.

```ruby
    sig { params(old_cask: Cask, new_cask: Cask).void }
    def self.reopen_apps_after_upgrade(old_cask, new_cask)
      bundle_ids = old_cask.artifacts
                           .grep(Artifact::Uninstall)
                           .flat_map(&:bundle_ids_to_reopen)
      return if bundle_ids.empty?

      # Re-register newly installed apps with Launch Services before reopening
      lsregister = Pathname(
        "/System/Library/Frameworks/CoreServices.framework" \
        "/Frameworks/LaunchServices.framework/Support/lsregister",
      )
      if lsregister.executable?
        new_cask.artifacts.grep(Artifact::App).each do |artifact|
          system(lsregister.to_s, "-f", artifact.target.to_s) if artifact.target.exist?
        end
      end

      ohai "Reopening #{bundle_ids.count} #{::Utils.pluralize("application",
                                                              bundle_ids.count)} closed during upgrade:"
      bundle_ids.each do |bundle_id|
        puts bundle_id
        system("open", "-b", bundle_id)
      end
    end
    private_class_method :reopen_apps_after_upgrade
```

Homebrew defines bundle_ids_to_reopen in Library/Homebrew/cask/artifact/abstract_uninstall.rb
```ruby
      # Line 74
      sig { returns(T::Array[String]) }
      def bundle_ids_to_reopen
        @bundle_ids_to_reopen ||= T.let([], T.nilable(T::Array[String]))
      end

      # Line 212
      # :quit/:signal must come before :kext so the kext will not be in use by a running process
      sig {
        params(
          bundle_ids: String,
          command:    T.nilable(T.class_of(SystemCommand)),
          upgrade:    T::Boolean,
          _kwargs:    T.anything,
        ).void
      }
      def uninstall_quit(*bundle_ids, command: nil, upgrade: false, **_kwargs)
        bundle_ids.each do |bundle_id|
          next unless running?(bundle_id)

          unless T.must(User.current).gui?
            opoo "Not logged into a GUI; skipping quitting application ID '#{bundle_id}'."
            next
          end

          ohai "Quitting application '#{bundle_id}'..."

          quit_succeeded = T.let(false, T::Boolean)
          begin
            Timeout.timeout(10) do
              Kernel.loop do
                next unless quit(bundle_id).success?

                next if running?(bundle_id)

                puts "Application '#{bundle_id}' quit successfully."
                quit_succeeded = true
                break
              end
            end
          rescue Timeout::Error
            opoo "Application '#{bundle_id}' did not quit. #{automation_access_instructions}"
          end

          bundle_ids_to_reopen << bundle_id if upgrade && quit_succeeded
        end
      end
```

Babble does not maintain application paths. Instead, after the upgrade completes, it queries Homebrew for the resolved installation path of each installed app artifact using brew info --json=v2 and consumes the artifact’s .target field. Application paths are discovered from Homebrew after the upgrade. Ref https://github.com/orgs/Homebrew/discussions/6946.

* JXA quit bundle IDs
* wait for LaunchServices teardown
* brew upgrade
* brew info --json=v2 | .artifacts[].target
* lsregister -f "$target"
* open -b "$bundle_id"

brew_info_json(token)
  .artifacts
  .select(&:app?)
  .map(&:target)

Homebrew remains the authoritative source for artifact placement. The mapping file contains only runtime policy, not installation metadata. `lsregister -f` eliminates the LaunchServices registration race before reopening applications by bundle ID.

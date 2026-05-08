<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# MacOSUpdate

## Purpose

macOS system update phase. Runs `softwareupdate --list` to
discover available updates and `softwareupdate --install` to
apply them. Babble surfaces this as a final phase after
brew/mas upgrades, with the user confirming whether to run
softwareupdate (which often triggers a reboot).

## Refactor/modular implementation

`refactor/ruby/lib/macos_updates.rb` plus several iterations
in `refactor/ruby/devel/`:
`macos_updates-v2-working-useme.rb`, `macos_updates-v2.1.rb`,
`macos_updates-v3.rb`, `macos_updates-v4-refactor.rb`. The
latest iteration (v4-refactor) was promoted to `lib/` locally
by the maintainer. Preserved at
`code-archive/refactor-modular/lib/macos_updates.rb` and the
devel versions.

v4-refactor introduces PTY-based subprocess management to
capture `softwareupdate`'s output while keeping stdin
connected for EULA / password prompts. The implementation is
partial — see [`../03-known-bugs-and-rough-edges.md`](../03-known-bugs-and-rough-edges.md)
§ "macOS updates: EULA acceptance and restart handling"
for the open issues.

Known bugs in v4-refactor:
- `require "logger"` fails on Ruby 3.4+ (logger extracted to
  separate gem)
- PTY error-handling paths are incomplete
- EULA acceptance from CLI is unreliable; some updates
  always require GUI acceptance
- Restart handling not addressed (the process dies on
  reboot)

Core flow attempted:

1. Run `softwareupdate --list` (or `--list --include-config-data`)
   to detect available updates
2. Parse the output for available updates
3. If updates available, prompt user with confirmation
4. Run `softwareupdate --install --all --restart` (or
   similar)
5. (Implicitly) the system reboots if updates require it

## Design ideas that survive the pivot

Limited:

- The phase placement (after brew/mas, before final cleanup)
- The user-confirmation gate before running softwareupdate
- Parsing `softwareupdate --list` output for the
  available-update count
- Handling the no-updates-available case (exit cleanly
  without prompting)

## Design ideas that don't survive

- **Trying to install macOS updates end-to-end from CLI.**
  The EULA / restart problems are not tractable without
  Apple-side cooperation that doesn't exist. See the
  03-known-bugs file for the proposed approach.
- **PTY-based subprocess management.** Replace with direct
  `system` for any commands that genuinely need stdin
  connected.
- **Multiple competing implementations in devel/.** W3 picks
  one approach and commits.

## Recommended W3 design (from `../03-known-bugs-and-rough-edges.md`)

Detect whether available updates require restart, and route
accordingly.

**Detection**: parse `softwareupdate --list --include-config-data`
output. Each update entry has a `Title:` line that may include
`Action: restart,` or `Action: shut down,`. Sample output:

```
* Label: macOS Ventura 13.5.1-22G90
    Title: macOS Ventura 13.5.1, Version: 13.5.1, Size: 1520555KiB, Recommended: YES, Action: restart,

* Label: MRTConfigData_10_15-1.93
    Title: MRTConfigData, Version: 1.93, Size: 4595KiB, Recommended: YES,
```

The first requires restart (note `Action: restart,`); the
second doesn't.

**Routing**:

1. List available updates with
   `softwareupdate --list --include-config-data`
2. Parse for `Action: restart,` and `Action: shut down,` per
   update
3. **If any restart-required updates exist:**
   - Display the restart-required list with a clear note:
     "To install, use the GUI Software Update pane."
   - Open the Software Update settings pane:
     ```sh
     /usr/bin/open x-apple.systempreferences:com.apple.Software-Update-Settings.extension
     ```
   - Exit cleanly; user proceeds in GUI.
   - (Optionally also list non-restart updates that the user
     could install separately, but that's friction; simpler
     to redirect to GUI for everything in this case.)
4. **If only non-restart updates exist:**
   - Install them via
     `softwareupdate --install <label> --no-scan`
     (per-label) or `softwareupdate --install --recommended
     --no-scan` (all recommended)
   - These typically don't require EULA acceptance and complete
     without a reboot
   - Config-data updates (XProtect, MRTConfigData,
     XProtectPayloads) particularly fit this case — small
     security-data updates that should just install

This sacrifices end-to-end automation only for the cases
where the EULA/restart problems would have broken the flow
anyway. Most security-data updates and small system updates
complete via babble; macOS major versions and Xcode-related
updates redirect to the GUI.

## Bugs / blockers found

`softwareupdate --list` is unstable across macOS versions —
the output format has changed between Big Sur, Monterey,
Ventura, Sonoma, Sequoia. Refactor/modular's parsing was
fragile across versions. W3 should test against the current
macOS release floor (macOS 14 Sonoma) and document version
expectations. Easier with the reduced scope (just listing,
not parsing for install confirmation).

## What feeds W3

- The phase orchestration shape (place after brew/mas)
- The user-display of available updates (read-only)
- Direct shell-out to `softwareupdate --list --include-config-data`
- Settings pane redirect via
  `/usr/bin/open x-apple.systempreferences:com.apple.Software-Update-Settings.extension`
- README documentation explaining why babble doesn't install
  macOS updates directly
- A path forward later: if Apple ever adds a reliable
  EULA-pre-acceptance flag or post-restart resumption
  mechanism, revisit

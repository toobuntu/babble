<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# BundleLauncher

## Purpose

Launches a macOS app by its CFBundleIdentifier, with
fallback paths if the simple `/usr/bin/open -b <id>` fails
(LaunchServices stale entries, missing registration, etc.).
The implementation in refactor/modular is sophisticated;
the planned W3 evolution is to delegate path resolution to
the seven-tier `Homebrew::CaskTools::BundleDiscovery` helper
extracted from cask-tools' `purge-quarantine` (W7).

## Refactor/modular implementation

`refactor/ruby/lib/utils/bundle_launcher.rb` (~257 lines).
The full file is preserved at
`code-archive/refactor-modular/lib/utils/bundle_launcher.rb`.

Public API:

```ruby
MacUtils::BundleLauncher.launch(bundle_id, timeout: 10)
```

Returns `true` on success; raises `OpenLaunchError` on
final failure.

Internal flow:

1. **Sanitize bundle_id** — strip control characters; check
   the `\A[a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+\z/i` shape
   (Apple's CFBundleIdentifier format)
2. **Try `/usr/bin/open -g -b <id>`** — with retry-with-backoff
   (`attempts < tries; sleep 0.15 * attempts`), up to 3
   attempts
3. **Wait for registration** — poll `lsappinfo info -only
   isregistered,isready` for up to `timeout` seconds; check
   for `LSApplicationHasRegistered=true` AND
   `LSApplicationHasSignalledItIsReady=true`
4. **On `OpenLaunchError`, fall back to path resolution**:
   - Tier A: `mdfind kMDItemCFBundleIdentifier == '<id>'`
   - Tier B: `lsregister -dump` parsing
   - The walker (`top_level_app`) handles nested .app
     bundles (e.g., `Adobe.app/Contents/Resources/Helper.app`),
     using PlistBuddy to validate `CFBundleIdentifier`
5. **Force LS registration** (`lsregister -f <path>`) if
   path is found
6. **Retry the open** with explicit path

Plus a launchctl-asuser fallback for GUI session
inheritance:

```ruby
def attempt_launch_in_gui_session(bundle_id)
  uid = Process.uid.to_s
  out, err, st = Open3.capture3(
    "launchctl", "asuser", uid, "/usr/bin/open", "-g", "-b", bundle_id
  )
end
```

Plus a custom `OpenLaunchError` class with `stdout`, `stderr`,
`status` attributes and a `to_h` method for structured logging.

## Comparison: cask-tools' purge-quarantine seven-tier discovery

`homebrew-cask-tools/cmd/purge-quarantine.rb` implements
seven discovery tiers for the same problem (find app
bundles by token):

1. **Caskroom version directory** — direct glob
   (`HOMEBREW_CASKROOM/<token>/*/*` filtered by
   `Contents/Info.plist` presence)
2. **Cask::CaskLoader** — Moved + uninstall.delete artifacts
   from the live cask definition
3. **.metadata JSON** — read from filesystem (works after
   the cask is removed from all taps)
4. **lsregister registry** — with 5-minute cache at
   `HOMEBREW_CACHE/purge-quarantine/lsregister.dump`
5. **pkgutil receipt database** — for pkg-installed casks
6. **pkgutil BOM** — Bill of Materials extraction for
   .pkg files still in Caskroom
7. **mdfind / Spotlight** — last resort

This is materially more sophisticated than refactor/modular's
three-tier (mdfind → lsregister → walker). The W3 plan is to
extract this seven-tier as a shared helper (W7 in master-plan)
and have BundleLauncher consume it.

## Design ideas that survive the pivot

- The retry-with-backoff on initial `/usr/bin/open`
- The launchctl-asuser GUI session fallback
- The `wait_until_reopened` post-launch verification (poll
  for LSApplicationHasRegistered AND
  LSApplicationHasSignalledItIsReady)
- The custom error class shape (`OpenLaunchError` with
  structured fields)
- The bundle-id syntax validation (Apple's regex)

## Design ideas that don't survive

- The three-tier discovery (mdfind → lsregister → walker).
  Replaced by the seven-tier `BundleDiscovery` helper from
  cask-tools.
- The 0.5-second polling interval in `wait_until_reopened`
  could be tighter (250ms is plenty for foreground apps);
  small refinement for W3.
- The `MacUtils::*` namespace. W3 collapses to `Babble::*`.

## Bugs / blockers found

PR #1's bundle_launcher equivalent had its own issues — see
`../reviews/pr1-review.md` § B2 (lsregister polling 0.2s
interval blocks for minutes). Refactor/modular's version is
better but not perfect; the polling delay above is the same
class of issue at lower severity.

## What feeds W3

- The full ~257-line refactor/modular implementation as
  the design baseline (saved at
  `code-archive/refactor-modular/lib/utils/bundle_launcher.rb`)
- The fallback structure: open → wait → on-error fall through
  to BundleDiscovery → register → re-open
- The custom error class
- Sorbet sig comments (currently disabled in refactor/modular;
  enable in W3)

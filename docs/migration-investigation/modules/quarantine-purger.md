<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# QuarantinePurger

## Purpose

Removes the `com.apple.quarantine` extended attribute from
installed cask bundles after upgrades. This is what allows
Gatekeeper to launch downloaded apps without the "<App> is
from an unidentified developer" dialog on every launch.

The babble role: opt-in delegation only. Cask-tools' `brew
purge-quarantine` already does this comprehensively;
babble's job is to invoke it (when the user wants) and not
duplicate.

## Refactor/modular implementation

The branch had its own `quarantine-purger` work in the early
prototype (`archive/babble/ruby/refactor/ruby/lib/`) but the
implementation never made it into refactor/modular's `lib/`.
The maintainer recognized that cask-tools' `brew
purge-quarantine` was the right home and stopped duplicating.

PR #1's `quarantine_purger.rb` was a single-tier glob through
the Caskroom directory — substantially less sophisticated than
cask-tools' seven-tier discovery. PR review § B7 documents
this as a regression.

## Cask-tools' implementation

`homebrew-cask-tools/cmd/purge-quarantine.rb` (~600 lines,
`# typed: strict`). Seven-tier bundle discovery:

1. Caskroom version directory glob
2. Cask::CaskLoader Moved + uninstall.delete artifacts
3. .metadata JSON on disk
4. lsregister registry (5-min cache at
   `HOMEBREW_CACHE/purge-quarantine/lsregister.dump`)
5. pkgutil receipt database
6. pkgutil BOM via lsbom
7. mdfind / Spotlight

Cleared the W7 inspiration: extract the seven-tier logic to
a shared `Homebrew::CaskTools::BundleDiscovery` class so both
`purge-quarantine` and the future babble can consume it
without duplicating the discovery code.

## Design ideas that survive the pivot

None within babble. The W3 babble:
- Does NOT include its own quarantine purger
- Optionally invokes cask-tools' `brew purge-quarantine` as
  a post-upgrade phase
- Documents this in the README as a recommended companion
  install: "For optimal experience, also install
  homebrew-cask-tools to get `brew purge-quarantine`."

The W7 BundleDiscovery extraction (cask-tools refactor) is a
separate workstream that benefits both purge-quarantine and
babble's BundleLauncher. See `master-plan.md` § W7.

## Design ideas that don't survive

The entire homemade quarantine purger. Drop.

## Bugs / blockers found

PR #1 review § B7: PR #1's homemade purger is single-tier
(glob Caskroom contents only), missing the metadata JSON,
pkgutil receipts, pkgutil BOM, and Spotlight tiers that
cask-tools handles. PR #1 would silently miss apps installed
via .pkg, apps no longer in any tap, apps in non-standard
locations.

## What feeds W3

- A documentation pointer to cask-tools as the canonical
  quarantine purger
- An opt-in invocation: post-upgrade, if cask-tools is
  installed, offer to run `brew purge-quarantine` against
  the upgraded casks
- A graceful skip if cask-tools is not installed (don't
  fail; just note that purge-quarantine is unavailable)
- The W7 cross-cutting work to extract `BundleDiscovery`
  from purge-quarantine (separate workstream; benefits
  babble's `BundleLauncher` too)

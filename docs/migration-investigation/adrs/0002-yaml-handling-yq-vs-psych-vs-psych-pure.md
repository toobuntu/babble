<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# ADR-0002: YAML handling — yq vs. Psych vs. psych-pure

- **Status:** Accepted
- **Deciders:** maintainer
- **Date:** 2026-05

## Context and problem statement

Babble's `babble.apps.yml` is a user-maintained YAML file. The
maintainer's workflow includes adding comments to entries that
explain why a particular app is configured a particular way
(e.g., why `unsafe_to_quit: true`, why a particular helper bundle
ID is in `quit` but not `reopen`, why a custom `quit_message`).
These comments are part of the user's data; destroying them is
data loss.

Babble also reorganizes the file at startup: sorts `apps.homebrew[]`
by token, sorts `apps.mas[]` by name, sorts each entry's
`bundle_ids` alphabetically, detects duplicate tokens. The
reorganize is a YAML round-trip: read → reorder → write. The
question: which YAML library to use such that the round-trip
**preserves comments**.

## Decision drivers

- **Comment preservation through round-trip**: required.
- **Availability in third-party Homebrew taps**: required.
  Homebrew permits gem installation only from `dev-cmd/` (in
  the `Homebrew/brew` repository); external commands in
  third-party taps cannot install gems.
- **Speed**: secondary; the file is small.
- **Maintenance overhead**: secondary; one-time integration cost
  is acceptable.

## Considered options

### Option 1 — Stdlib `Psych` (Ruby's default YAML library)

Use the YAML library shipped with Ruby. Available everywhere;
zero external dependencies.

**Pros:**
- No external dependency
- Zero install cost
- Same library Homebrew uses internally
- Battle-tested

**Cons:**
- **Comments are stripped on parse and not preserved on emit.**
  A round-trip silently destroys user comments.
- This is the dealbreaker. Any reorganize-on-startup using
  Psych is a data-loss bug waiting to bite the maintainer.

**Disposition:** Rejected for round-trip use. Acceptable for
parse-only operations (loading the file, validating, NOT
re-emitting to disk).

### Option 2 — `psych-pure` gem

Kevin Newton's pure-Ruby YAML 1.2 implementation
([blog post](https://kddnewton.com/2025/12/25/psych-pure.html),
[github](https://github.com/kddnewton/psych-pure)) — supports
comment preservation through round-trips. On the surface, the
ideal solution.

**Pros:**
- Comment preservation works correctly
- Pure Ruby; no native compilation
- Modern, actively maintained
- API similar enough to Psych that adoption is straightforward

**Cons:**
- **Cannot be installed by third-party Homebrew taps.**
  Homebrew restricts gem installation to dev-cmds in the
  `Homebrew/brew` repository. External commands in
  third-party taps (like babble) cannot bundle their own
  gems.
- Bundling psych-pure as a vendored copy would work
  technically but bypasses Homebrew's gem-management story
  and is the kind of thing that breaks across Homebrew
  upgrades
- Cask-tools encountered the same constraint with
  `generate-tap-man-completions`. The workaround (hardlinking
  it into Homebrew's `dev-cmd/`) is hacky and unmaintainable

**Disposition:** Rejected for distribution despite ideal
functionality. Revisit if Homebrew opens up gem installation
for external commands in the future.

### Option 3 — Shell out to `yq`

Use the `yq` command-line tool (Mike Farah's Go-based YAML
processor; brew formula `yq`). yq preserves comments natively
across reorganize operations.

**Pros:**
- Comment preservation works correctly
- yq is a Homebrew formula; can be declared as `depends_on
  "yq"` in babble's formula
- The reorganize operation expresses cleanly as a yq
  expression (`.apps.homebrew |= sort_by(.token) | ...`)
- Already proven: refactor/modular used this approach with
  the maintainer's daily workflow for a year+
- Performance is acceptable for the small file sizes involved
  (~hundreds of entries at most)

**Cons:**
- External dependency. Users must have yq installed for
  reorganize to work.
- Shell-out overhead per reorganize (small; one process
  launch)
- yq's expression language is its own learning curve
  (mitigated: babble's reorganize logic is one fixed expression
  that the user never sees)
- Fragility risk: yq's expression language has changed across
  major versions; pinning to a known-working subset is
  important

**Disposition:** Accepted as primary. yq becomes a runtime
dependency declared in babble's Homebrew formula.

### Option 4 — Don't reorganize at all

Skip the round-trip entirely. The user is responsible for
maintaining sort order in their `babble.apps.yml`.

**Pros:**
- No YAML round-trip; no comment-preservation problem
- Zero external dependencies
- Simplest possible implementation

**Cons:**
- The maintainer's daily-use experience benefits from
  auto-sort (it's how the original ksh+yq workflow worked)
- Users adding new entries to a long file would face merge
  hassle if they don't manually sort
- Loses a meaningful quality-of-life feature

**Disposition:** Rejected. The feature is valuable; the
maintenance burden of yq dependency is acceptable.

### Option 5 — Manual byte-level patching of YAML strings

Read the file as text. Apply minimal text transformations
(e.g., re-sort lines within `bundle_ids:` arrays) without
parsing as YAML.

**Pros:**
- Comments preserved (we never re-emit)
- No external dependencies
- Pure Ruby

**Cons:**
- Fragile to YAML format variations (block-style vs. flow-style,
  quoted vs. unquoted scalars, anchor/alias references,
  multi-line strings, etc.)
- Implementing a sort-within-section text transformation that
  handles all valid YAML variants requires writing a
  custom-but-incomplete YAML parser \u2014 essentially reimplementing
  Psych badly
- High risk of corrupting the file on edge cases the
  implementer didn't anticipate

**Disposition:** Rejected. Too fragile for production use.

## Decision outcome

**Chosen: Option 3 (yq).**

W3 implementation:

1. babble's Homebrew formula declares `depends_on "yq"`
2. `Babble::Config::Reorganizer` shells out to `yq` for the
   reorganize-on-startup behavior
3. `Babble::Config::Validator` uses stdlib `Psych` for
   parse-only operations (loading, validating, duplicate
   detection \u2014 these don't need round-trip)
4. If yq is somehow missing at runtime (manually uninstalled
   despite being a formula dependency), the reorganize step
   emits an `opoo` warning and skips; the user's data is
   preserved (no destructive round-trip), the rest of babble
   continues normally
5. No fallback to manual text patching, no fallback to
   psych-pure, no auto-vendoring

## Consequences

**Good:**
- Comment preservation works correctly via a battle-tested tool
- yq is a real Homebrew formula; install path is clean
- The reorganize implementation is small (one `yq` invocation
  in a Ruby `Open3.capture3` wrapper)
- If yq's behavior changes in a future version, we can pin
  the formula version in our `depends_on` declaration

**Bad:**
- Adds yq as a runtime dependency
  (~10 MB of disk; trivial)
- Shell-out overhead per babble run (one yq invocation;
  ~50ms)
- yq's expression language must be learned by anyone modifying
  babble's reorganize logic (small surface area; one
  expression)

**Tradeoff acknowledged:** the dependency-on-yq cost is
acceptable. Babble already depends on Homebrew, mas, Xcode
command-line tools (for swiftc), and indirectly on the running
GUI session. Adding yq is incremental.

## More information

- psych-pure gem: https://github.com/kddnewton/psych-pure
- psych-pure announcement:
  https://kddnewton.com/2025/12/25/psych-pure.html
- Mike Farah's yq: https://github.com/mikefarah/yq
- Homebrew formula: https://formulae.brew.sh/formula/yq

## Revisit triggers

- **Homebrew opens up gem installation for external commands
  in third-party taps.** psych-pure becomes viable as a pure-
  Ruby alternative; revisit whether dropping the yq dependency
  is worthwhile.
- **yq makes a major-version-incompatible change** that would
  require rewriting babble's reorganize expression. May be
  worth re-evaluating whether the reorganize feature is worth
  the maintenance burden, or whether the W3 alternative
  (manual maintenance by the user) is preferable.
- **psych-pure is added to Homebrew's vendored gem list.**
  Direct path; no third-party-tap restriction. Becomes the
  obvious choice.
- **Apple ships a YAML library or yq equivalent in macOS by
  default**, eliminating the install-yq step.

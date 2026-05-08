<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# BrewUpdate

## Purpose

Runs `brew update`, parses its output to extract new formulae
and casks (so descriptions can be displayed), and opens
release-notes / changelog URLs in the user's browser when a
new Homebrew version was installed.

This is the metadata-refresh phase that happens before
`BrewUpgrade`. It also (in refactor/modular) does some
maintainer-specific housekeeping: moving `~/.Brewfile` to
`~/.config/homebrew/Brewfile` if present.

## Refactor/modular implementation

`refactor/ruby/lib/brew_update.rb`. The complete file is
preserved at `code-archive/refactor-modular/lib/brew_update.rb`.

Three modules in one file:

1. **`AtomicFileMover`** — `move(src, dst_dir, filename)`
   that preserves symlinks, otherwise atomic copy/move via
   tempfile.
2. **`BrewfileMover`** — uses AtomicFileMover to move
   `~/.Brewfile` → `~/.config/homebrew/Brewfile` if the
   former exists.
3. **`BrewUpdate`** — main module. `update_brew` runs
   `brew update`, parses output via `Open3.popen2e` line by
   line, captures new formula/cask names and release-notes URLs.

Key parsing logic in `update_brew`:

```ruby
case cleaned_line
when /^==>.*New Formulae/
  in_formulae_section = true
  in_casks_section = false
when /^==>.*New Casks/
  in_formulae_section = false
  in_casks_section = true
when /^==>.*(Outdated|Renamed|Deleted|Modified)/,
     /^You have/,
     /^Already up-to-date$/,
     /^The \d+\.\d+\.0 release notes are available on the Homebrew Blog:/,
     /^The .+ changelog can be found at:/
  in_formulae_section = false
  in_casks_section = false
else
  # Collect token lines in the relevant section
  if in_formulae_section
    formulae << cleaned_line unless cleaned_line.empty?
  elsif in_casks_section
    casks << cleaned_line unless cleaned_line.empty?
  end
end
```

Plus regex-based capture of release notes / changelog URLs:

```ruby
if %r{https://brew\.sh/blog/\d+\.\d+\.\d+}.match?(cleaned_line)
  release_notes = cleaned_line.strip
elsif line.include?("https://github.com/Homebrew/brew/releases/tag")
  changelog = cleaned_line.strip
end
```

After parsing, displays descriptions:

```ruby
unless formulae.empty?
  puts "\n\033[36m⨀=> \033[0m\033[1mDescriptions of New Formulae\033[0m\n"
  formulae.each do |formula|
    system("brew", "desc", "--formula", formula.to_s)
  end
end
```

And opens URLs via `HOMEBREW_BROWSER`/`BROWSER`/default-browser
fallback.

## Design ideas that survive the pivot

- The `Open3.popen2e` line-by-line parsing approach
- Capturing new formulae / casks for description display
- Release-notes and changelog URL extraction
- Browser preference: `HOMEBREW_BROWSER` →
  `BROWSER` → `/usr/bin/open -u`
- The `⨀=>` (now `==> ⨀` per the formatter decision)
  prefix for babble-emitted output

## Design ideas that don't survive

- **The duplicated description display** when Homebrew
  itself now provides descriptions inline in `brew update`
  output. See [`../03-known-bugs-and-rough-edges.md`](../03-known-bugs-and-rough-edges.md)
  § "brew_update fixme: descriptions duplicated by Homebrew"
  for the W3 detection-by-line-shape approach (with full
  parser pseudocode and rationale).
- **`AtomicFileMover` and `BrewfileMover`** — out of scope
  for babble. Drop entirely. The maintainer's
  `~/.Brewfile` migration is their concern, not babble's.
- **The brittle ANSI-stripping regex.** W3 either disables
  ANSI in captured output via `HOMEBREW_NO_COLOR=1` or uses
  a battle-tested gem.
- **Shelling out to `brew desc` via bare `system`.** As an
  external command, this becomes
  `safe_system HOMEBREW_BREW_FILE, "desc", "--formula", token`
  per Homebrew/brew's AGENTS.md guideline ("Prefer shelling
  out via `HOMEBREW_BREW_FILE` instead of requiring `cmd/`
  or `dev-cmd` when composing brew commands").
- **Shelling out to `brew update`.** Likewise:
  `safe_system HOMEBREW_BREW_FILE, "update"`. The
  line-by-line parsing has to capture output somehow; one
  approach is a custom IO that filters as the data flows
  through, or capture-then-display-then-process.
- **The 200-line commented-out alternative implementation
  at the bottom of the file.** Drop.

## Bugs / blockers found

See `../03-known-bugs-and-rough-edges.md` § "brew_update
fixme: descriptions duplicated by Homebrew" for the main
issue. The other rough edges (ANSI stripping brittleness,
Brewfile mover scope creep) are noted in the same file.

PR #1 didn't have a parallel BrewUpdate module in detail, so
the PR review docs don't cover this directly.

## What feeds W3

- The phase boundary (run brew update; parse output for new
  formulae/casks; show descriptions; open release notes URL
  if new version)
- The line-by-line parsing pattern, refined to detect
  Homebrew's inline-description format
- The browser-preference fallback (HOMEBREW_BROWSER → BROWSER
  → open)
- The release-notes / changelog URL capture
- Direct API calls instead of shell-outs

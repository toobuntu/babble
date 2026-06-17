<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Code archive

This directory holds full-content extracts of source files
from the archived branches. Each subdirectory corresponds to
one source. Files preserve their original SPDX headers if
present.

## Subdirectories

- `refactor-modular/` — extracts from
  `origin/refactor/modular` (the year+ of work). Primary
  source for design patterns and module shapes.
- `base64/` — the `NOTES.txt` content and any code-comment
  excerpts from `origin/base64` (the ksh-era base64 → comma
  transition).
- `pr1/` — selected extracts from
  `origin/copilot/rewrite-babble-as-ruby-app`. The branch
  was discarded (no archive tag) but the Swift `quit_alert.swift`
  has the auto-compile insight that informs ADR-0001, and
  the `IMPLEMENTATION_SUMMARY.md` is preserved as the
  archive of what Sonnet 4.6 thought it was doing.

## How to populate (maintainer runs locally)

The migration-investigation Phase 2 work writes the prose
documentation but does not extract the code archives —
extracting 50+ files via per-file MCP calls is fragile.
Instead, run the extraction commands below from the babble
worktree corresponding to each source branch.

The maintainer's existing worktrees:

```sh
git worktree list
# /Users/todd/devel/claude/desktop/toobuntu/babble                  [main]
# /Users/todd/devel/claude/desktop/babble-base64           [base64]
# /Users/todd/devel/claude/desktop/toobuntu/babble-refactor-modular [refactor/modular]
```

(The PR-1 and PR-3 worktrees can be torn down before this
extraction work; they're not needed for archive purposes
since those branches are being discarded.)

### Extract from refactor/modular

Run from `~/devel/claude/desktop/toobuntu/babble-refactor-modular`:

```sh
cd ~/devel/claude/desktop/toobuntu/babble-refactor-modular
DEST=~/devel/claude/desktop/toobuntu/babble/docs/migration-investigation/code-archive/refactor-modular

# Mirror the relevant tree under refactor/ into the archive.
# Use rsync to preserve permissions and skip .git stuff.
mkdir -p "$DEST"
rsync --archive --verbose \
  --exclude='.git*' \
  --exclude='build/' \
  --exclude='*.png_base64.txt' \
  --exclude='*.svg_base64.txt' \
  --include='*/' \
  --include='*.rb' \
  --include='*.swift' \
  --include='*.yml' \
  --include='*.yaml' \
  --include='*.sh' \
  --include='TODO' \
  --include='*-fixme.txt' \
  --include='NOTES.txt' \
  --include='README.md' \
  --include='*.md' \
  --exclude='*' \
  refactor/ "$DEST/refactor/"

# Verify extraction
find "$DEST" -type f | wc -l   # expect 60-90 files
du -sh "$DEST"                  # expect ~500KB-1MB
```

Note: the rsync filters preserve directory structure under
`refactor/`. After extraction, the layout under `$DEST` will be:

```
refactor-modular/refactor/
├── ruby/
│   ├── lib/                 # the working modules
│   ├── ui/
│   ├── utils/
│   ├── devel/               # design iterations
│   ├── completions/
│   ├── TODO
│   ├── unified-config.yml
│   └── .Babblefile.yml
├── swift/
│   ├── src/                 # quit_alert.swift sources
│   └── (build/ excluded)
├── bin/
│   └── babble
└── script/
```

### Extract from base64 branch

Run from `~/devel/claude/desktop/babble-base64`:

```sh
cd ~/devel/claude/desktop/babble-base64
DEST=~/devel/claude/desktop/toobuntu/babble/docs/migration-investigation/code-archive/base64

mkdir -p "$DEST"

# The notable content: the bbl ksh script with base64 logic
# and the NOTES.txt preserved in this branch.
cp NOTES.txt "$DEST/NOTES.txt"

# The full bbl on this branch shows the base64 approach
# (later replaced by comma in main). Save as bbl.base64-era
# to distinguish from main's current bbl.
cp bbl "$DEST/bbl.base64-era"

# Verify
ls -la "$DEST"
```

### Extract selected files from PR #1

The branch is being discarded (no archive tag), but two
files are worth preserving:

Run from `~/devel/claude/desktop/babble-pr1`:

```sh
cd ~/devel/claude/desktop/babble-pr1
DEST=~/devel/claude/desktop/toobuntu/babble/docs/migration-investigation/code-archive/pr1

mkdir -p "$DEST"

# Swift quit_alert (the auto-compile source — informs ADR-0001)
if [ -f swift/src/quit_alert.swift ]; then
  cp swift/src/quit_alert.swift "$DEST/quit_alert.swift"
fi

# The implementation summary written by Sonnet 4.6
if [ -f IMPLEMENTATION_SUMMARY.md ]; then
  cp IMPLEMENTATION_SUMMARY.md "$DEST/IMPLEMENTATION_SUMMARY.md"
fi

# The bin/babble Bash wrapper (interesting for the
# alternative approach to portable-Ruby resolution; PR
# review § S1 references this)
if [ -f bin/babble ]; then
  cp bin/babble "$DEST/bin-babble"
fi

# Verify
ls -la "$DEST"
```

## Add SPDX headers

After extraction, run the annotate script (assuming it's
been copied in as part of W2 setup):

```sh
cd ~/devel/claude/desktop/toobuntu/babble
bash scripts/annotate.sh

# Verify reuse compliance
reuse lint
```

The annotate.sh handles files that already have SPDX headers
(no-op) and files that need headers added (adds them).
Files that came from refactor/modular generally already have
headers — it's a no-op for those.

## After extraction

Once the code-archive is populated, the migration-investigation
PR is ready to commit. The maintainer:

1. Reviews the extracted files (browse a few; confirm
   nothing surprising)
2. Stages everything: `git add docs/migration-investigation/`
3. Commits with the W2 commit message
4. Pushes the `preservation-archive` branch
5. Opens the PR
6. After merge, runs the archive tag commands (next file)

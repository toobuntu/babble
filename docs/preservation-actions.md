<!--
SPDX-FileCopyrightText: Copyright 2026 Todd Schulman

SPDX-License-Identifier: GPL-3.0-or-later
-->

# Action items — babble migration investigation archive (W2)

This is W2 in `~/devel/claude/desktop/workspace/master-plan.md`.
The goal: clean up dead/stale branches first, then preserve the
year+ of Ruby-port investigation as durable documentation BEFORE
the W3 external-command pivot rewrites everything.

You committed to the external command pending this preservation.
This document gates the pivot.

## Two-step shape: cleanup, then preservation

Earlier drafts of this gave a confused decision-axis ("Option C"
turned out to be a re-statement of "Option A"). The actual
resolution:

- **Step 1: Branch triage and cleanup.** Read each WIP branch,
  decide whether it has any salvageable diff worth landing on
  main, and either consolidate the work or mark the branch for
  archive. Goal: smaller archive surface (probably 2 tags
  instead of 4), with any genuinely useful diffs from dead
  branches captured on main pre-tag.
- **Step 2: Preservation.** Archive the surviving branches with
  date-prefixed tags; build the `docs/migration-investigation/`
  directory of prose + code-archive material; cross-link from
  babble's existing docs.

No work is done to make Ruby actually run pre-pivot. Bug fixes
in PR #1's Ruby code are out of scope. The release path remains:
ksh v0.5.2 (current main) → external command v0.6.0 (W3). No
intermediate Ruby release.

## Pre-Claude-Code: confirm starting state

Verify the babble repo state before launching:

```sh
cd ~/devel/claude/desktop/toobuntu/babble
git status                       # clean on main
git fetch --all --prune
git branch --all --sort=-committerdate
```

You should see at least:
- `main` (current ksh, v0.5.1 + the small print-statement diff)
- `remotes/origin/copilot/rewrite-babble-as-ruby-app` (PR #1)
- `remotes/origin/copilot/fix-terminal-upgrade-issue` (PR #3)
- `remotes/origin/refactor/modular` (older WIP)
- `remotes/origin/base64` (older WIP)
- and any other branches you've pushed

Note the branch list — the Claude Code session reads each, then
proposes a triage outcome.

## Pre-Claude-Code: snapshot the archive directory

The repo has `archive/babble/ruby/refactor/ruby/lib/` containing
prototype Ruby files from before the `rm -rf`. The Claude Code
session reads these to populate
`docs/migration-investigation/code-archive/`. Verify they're
present:

```sh
ls -la ~/devel/claude/desktop/toobuntu/babble/archive/babble/ruby/refactor/ruby/lib/
ls -la ~/devel/claude/desktop/toobuntu/babble/archive/babble/ruby/refactor/ruby/lib/utils/
ls -la ~/devel/claude/desktop/toobuntu/babble/archive/babble/ruby/refactor/ruby/lib/macos_interface/
```

Expected files include `brew_cask_utils.rb`, `brew_update.rb`,
`brew_upgrade.rb`, `macos_updates.rb`, `running_gui_bundle_ids.rb`,
`mas_token_generator.rb`, `dark_mode.rb`, `display_alert.rb`, and
others.

If any are missing, the preservation work has less to draw on —
flag in the Claude Code session so the agent doesn't fabricate.

## Pre-Claude-Code: ensure scripts/ has what W2 needs

W2 needs `scripts/sandbox-enter.sh` (to enter Tier 3) and
`scripts/annotate.sh` (for SPDX). The repo doesn't yet have
either. Copy from blackoutd before launching:

```sh
cd ~/devel/claude/desktop/toobuntu/babble
mkdir -p scripts
cp ~/devel/claude/desktop/toobuntu/blackoutd/scripts/sandbox-enter.sh scripts/
cp ~/devel/claude/desktop/toobuntu/blackoutd/scripts/sandbox-exit.sh scripts/
cp ~/devel/claude/desktop/toobuntu/blackoutd/scripts/annotate.sh scripts/
chmod +x scripts/*.sh
```

If repo-foundation (W1) has already been bootstrapped and pushed,
prefer using its versions instead. But for the W2 session, the
blackoutd scripts work fine.

## Claude Code session: triage + preservation

Run at Tier 3 from `~/devel/claude/desktop/toobuntu/babble/`:

```sh
cd ~/devel/claude/desktop/toobuntu/babble
./scripts/sandbox-enter.sh --mode=no-remote
# Enter the sandbox dir; launch Claude Code from there.
```

The Claude Code prompt is at
`~/devel/claude/desktop/toobuntu/babble/docs/preservation-prompt.md`. Copy
the prompt body (between `>>>` markers) and paste.

When Claude Code reports back, it will provide:

1. A triage summary: per-branch decision (consolidate, archive,
   discard) with rationale
2. A list of any cleanup commits proposed for main
3. The `docs/migration-investigation/` directory, populated
4. The exact `git tag` commands to run after the PR merges,
   with `$(date -j +%Y-%m-%d)` substitution intact

Review the triage decisions specifically — these are judgment
calls and you should sanity-check them. If any branch's fate
seems wrong, push back and ask the agent to revise.

After approving the triage:

1. Exit the sandbox.
2. Fetch the branch from the sandbox:

   ```sh
   cd ~/devel/claude/desktop/toobuntu/babble
   git fetch /tmp/babble-sandbox/.git \
     preservation-archive:preservation-archive
   git switch preservation-archive
   ```

3. Review the new `docs/migration-investigation/` directory:

   ```sh
   tree ~/devel/claude/desktop/toobuntu/babble/docs/migration-investigation/
   ```

4. Read `00-meta-overview.md` and `01-decisions.md` carefully —
   these are the high-traffic entry points.
5. Spot-check 2-3 of the `modules/*.md` files.
6. Spot-check 1-2 of the `code-archive/*.{rb,swift}` files —
   confirm they're complete extracts and not summaries.
7. If the agent proposed cleanup commits to land on main first
   (e.g., cherry-picks from a dead branch), review and apply
   those manually before pushing the preservation branch.
8. Push and merge:

   ```sh
   git push origin preservation-archive
   gh pr create --base main \
     --title "Preserve Ruby migration investigation" \
     --body "..."
   ```

## Post-Claude-Code: tag the surviving branches

Run the `git tag` commands the Claude Code session provided.
Example shape (substitute actual branch list):

```sh
TODAY=$(date -j +%Y-%m-%d)

git tag --sign --annotate "archive/${TODAY}-pr1-rewrite" \
  --message "Archived: PR #1 (Ruby modular rewrite)" \
  origin/copilot/rewrite-babble-as-ruby-app

git tag --sign --annotate "archive/${TODAY}-pr3-terminal" \
  --message "Archived: PR #3 (terminal exclusion)" \
  origin/copilot/fix-terminal-upgrade-issue

git push origin --tags
```

Branches that the triage discarded don't get tags.

After tagging, branches CAN be deleted (the tags preserve them in
git's history). Discarded branches: delete now. Archived branches:
keep for the W3 cherry-pick reference window, then delete after
W3 lands. Any branches consolidated into main: delete.

## Post-Claude-Code: confirm before W3

- [ ] `docs/migration-investigation/` PR merged to main
- [ ] Archive tags pushed and visible at
      https://github.com/toobuntu/homebrew-babble/tags
- [ ] Discarded branches deleted both locally and on remote
- [ ] Sandbox cleaned up
- [ ] You've read enough of the new
      `docs/migration-investigation/` to feel confident the
      work is preserved
- [ ] You feel ready to commit fully to the W3 external-command
      pivot

If any of these aren't met, pause before W3.

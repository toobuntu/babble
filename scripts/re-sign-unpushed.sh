#!/bin/sh
# POSIX [ ] tests are deliberate (dash-compatible; ksh -n clean) and queued as an
# improvement for the repo-foundation canonical. brew style forces shellcheck
# --shell=bash --enable=all (style.rb) regardless of shebang, so the optional
# require-double-brackets preference must be exempted (numeric code: the named
# form is not valid in disable= directives).
# shellcheck disable=SC2292
# This file is a hand-copy of toobuntu/repo-foundation/scripts/re-sign-unpushed.sh, staged ahead of
# the first RF sync; do not modify it directly.
# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later
#
# re-sign-unpushed.sh -- re-sign the unpushed, unsigned commits a sandboxed
# agent left behind, then push what was re-signed. For each repo argument
# (default: the current repo):
#
#   1. find the oldest UNSIGNED commit not yet on any remote -- so published
#      history is never rewritten, and a remoteless repo re-signs only its
#      unsigned tip rather than its already-signed base;
#   2. if one exists: rebase from just before it, re-signing each replayed
#      commit, then push the branch -- --set-upstream when origin does not
#      know the branch yet, a fast-forward push when origin still descends
#      it, a lease-pinned force when a post-review amend/rebase diverged.
#      Each outcome announces itself. A local-only repo (no origin remote)
#      re-signs and stops with a note.
#   3. if nothing needed re-signing: this is NOT a stand-in for git push --
#      nothing is pushed. Up to date: says so (exit 0). Branch ahead of or
#      unknown to origin: prints the exact push command to run and exits 2.
#
# Detached HEAD is skipped with a note. The .githooks/pre-push gate is the
# backstop -- it rejects any unsigned commit this misses. POSIX sh; no
# bashisms.

set -eu

resign_one() {
  repo_dir=$1
  branch=$(git -C "${repo_dir}" branch --show-current)

  if ! git -C "${repo_dir}" rev-parse --quiet --verify HEAD >/dev/null 2>&1
  then
    printf '%s (%s): no commits yet; skipping\n' "${repo_dir}" "${branch}"
    return 0
  fi

  if [ -z "${branch}" ]
  then
    printf '%s: detached HEAD; nothing to push, skipping\n' "${repo_dir}"
    return 0
  fi

  has_origin=1
  git -C "${repo_dir}" config --get remote.origin.url >/dev/null 2>&1 || has_origin=0
  remote_ref="refs/remotes/origin/${branch}"

  # Oldest unsigned commit among those not on any remote. The pipeline prints
  # the first match and breaks; the command substitution captures it.
  oldest_unsigned=$(
    git -C "${repo_dir}" rev-list --reverse HEAD --not --remotes |
      while IFS= read -r oid
      do
        if [ "$(git -C "${repo_dir}" log -1 --format='%G?' "${oid}")" = N ]
        then
          printf '%s\n' "${oid}"
          break
        fi
      done
  )

  if [ -z "${oldest_unsigned}" ]
  then
    # Nothing was re-signed, so nothing is pushed: publishing here would make
    # this a generic-push tool. Report the state; when a push is still
    # pending, hand over the exact command and exit 2 so the pending state
    # cannot be missed.
    if [ "${has_origin}" -eq 0 ]
    then
      printf '%s (%s): already signed; local-only repo (no origin remote), nothing to push\n' \
        "${repo_dir}" "${branch}"
      return 0
    fi
    if ! git -C "${repo_dir}" rev-parse --quiet --verify "${remote_ref}" >/dev/null 2>&1
    then
      printf '%s (%s): already signed; nothing re-signed, so NOT pushing the new branch.\n' \
        "${repo_dir}" "${branch}" >&2
      printf '  To push: git -C %s push --set-upstream origin %s\n' "${repo_dir}" "${branch}" >&2
      return 2
    fi
    if [ "$(git -C "${repo_dir}" rev-parse HEAD)" = "$(git -C "${repo_dir}" rev-parse "${remote_ref}")" ]
    then
      printf '%s (%s): already signed; origin/%s is current, nothing to push\n' \
        "${repo_dir}" "${branch}" "${branch}"
      return 0
    fi
    printf '%s (%s): already signed; nothing re-signed, so NOT pushing (origin/%s differs).\n' \
      "${repo_dir}" "${branch}" "${branch}" >&2
    printf '  To push: git -C %s push origin HEAD:%s\n' "${repo_dir}" "${branch}" >&2
    return 2
  fi

  if git -C "${repo_dir}" rev-parse --quiet --verify "${oldest_unsigned}^" >/dev/null 2>&1
  then
    git -C "${repo_dir}" rebase --exec 'git commit --amend --no-edit --gpg-sign' "${oldest_unsigned}^"
  else
    git -C "${repo_dir}" rebase --root --exec 'git commit --amend --no-edit --gpg-sign'
  fi

  # Push what was just re-signed.
  if [ "${has_origin}" -eq 0 ]
  then
    printf '%s (%s): re-signed; local-only repo (no origin remote), nothing to push\n' \
      "${repo_dir}" "${branch}"
    return 0
  fi
  if ! git -C "${repo_dir}" rev-parse --quiet --verify "${remote_ref}" >/dev/null 2>&1
  then
    printf '%s (%s): re-signed; origin has no such branch, pushing with --set-upstream\n' \
      "${repo_dir}" "${branch}"
    git -C "${repo_dir}" push --set-upstream origin "HEAD:${branch}"
  elif git -C "${repo_dir}" merge-base --is-ancestor "${remote_ref}" HEAD
  then
    printf '%s (%s): re-signed; pushing (fast-forward)\n' "${repo_dir}" "${branch}"
    git -C "${repo_dir}" push origin "HEAD:${branch}"
  else
    printf '%s (%s): re-signed; pushing (force-with-lease; origin diverged)\n' "${repo_dir}" "${branch}"
    git -C "${repo_dir}" push \
      --force-with-lease="refs/heads/${branch}:$(git -C "${repo_dir}" rev-parse "${remote_ref}")" \
      origin "HEAD:${branch}"
  fi
}

if [ "$#" -eq 0 ]
then
  set -- "${PWD}"
fi

rc=0
for repo in "$@"
do
  resign_one "${repo}" || rc=$?
done
exit "${rc}"

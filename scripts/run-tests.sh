#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Run brew tests for the babble command.
#
# brew tests only finds specs inside $(brew --repo)/Library/Homebrew/test/.
# This script creates temporary hardlinks (not symlinks — parallel_rspec uses
# File.stat which follows symlinks but requires the link target to be resolved
# relative to the Homebrew working directory) then unlinks them on exit.
#
# The cmd/babble/ subtree must be hardlinked alongside cmd/babble.rb: the
# hardlinked command's `require_relative "babble/..."` resolves relative to
# the hardlink location, and brew's command discovery only scans cmd/*.rb,
# so the subtree files do not become phantom commands.
#
# Usage:
#   chmod +x scripts/run-tests.sh
#   scripts/run-tests.sh [--only=cmd/<file>[:<line>]]
#
# Do NOT run other brew commands while this script is active. In particular:
#   - brew update / brew upgrade   — may run `git fetch` inside $(brew --repo)
#   - brew update-reset            — runs `git reset --hard && git clean -fd`,
#                                    which removes untracked files including the
#                                    hardlinked copies of our files
#   - brew cleanup / brew autoremove
#
# If any of those commands are run concurrently, brew tests may fail or produce
# incorrect results. The EXIT trap below removes the hardlinks when this script
# finishes (or is interrupted), but cannot protect against concurrent git clean.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TAP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BREW_REPO="$(brew --repo)"
HOMEBREW_LIB="${BREW_REPO}/Library/Homebrew"

BABBLE_CMD_SRC="${TAP_DIR}/cmd/babble.rb"
BABBLE_SPEC_SRC="${TAP_DIR}/test/cmd/babble_spec.rb"
BABBLE_CMD_DST="${HOMEBREW_LIB}/cmd/babble.rb"
BABBLE_SPEC_DST="${HOMEBREW_LIB}/test/cmd/babble_spec.rb"

VERSION_LIB_SRC="${TAP_DIR}/cmd/babble/version.rb"
VERSION_LIB_DST="${HOMEBREW_LIB}/cmd/babble/version.rb"

FMT_LIB_SRC="${TAP_DIR}/cmd/babble/formatter.rb"
FMT_SPEC_SRC="${TAP_DIR}/test/cmd/babble/formatter_spec.rb"
FMT_LIB_DST="${HOMEBREW_LIB}/cmd/babble/formatter.rb"
FMT_SPEC_DST="${HOMEBREW_LIB}/test/cmd/babble/formatter_spec.rb"

SH_LIB_SRC="${TAP_DIR}/cmd/babble/sh.rb"
SH_SPEC_SRC="${TAP_DIR}/test/cmd/babble/sh_spec.rb"
SH_LIB_DST="${HOMEBREW_LIB}/cmd/babble/sh.rb"
SH_SPEC_DST="${HOMEBREW_LIB}/test/cmd/babble/sh_spec.rb"

AM_LIB_SRC="${TAP_DIR}/cmd/babble/app_manager.rb"
AM_SPEC_SRC="${TAP_DIR}/test/cmd/babble/app_manager_spec.rb"
AM_LIB_DST="${HOMEBREW_LIB}/cmd/babble/app_manager.rb"
AM_SPEC_DST="${HOMEBREW_LIB}/test/cmd/babble/app_manager_spec.rb"

# The fixture lives in a babble-owned subdir of brew's fixtures tree —
# created here, removed on cleanup — so it can never collide with brew's.
FIXTURE_SRC="${TAP_DIR}/test/support/fixtures/babble/lsappinfo_list_sample.txt"
FIXTURE_DST="${HOMEBREW_LIB}/test/support/fixtures/babble/lsappinfo_list_sample.txt"

cleanup() {
  local exit_code=$?
  echo "" >&2
  echo "==> Removing hardlinks from Homebrew repository..." >&2
  rm -f "${BABBLE_CMD_DST}" "${BABBLE_SPEC_DST}"
  rm -f "${VERSION_LIB_DST}"
  rm -f "${FMT_LIB_DST}" "${FMT_SPEC_DST}"
  rm -f "${SH_LIB_DST}" "${SH_SPEC_DST}"
  rm -f "${AM_LIB_DST}" "${AM_SPEC_DST}"
  rm -f "${FIXTURE_DST}"
  rmdir "${HOMEBREW_LIB}/cmd/babble" "${HOMEBREW_LIB}/test/cmd/babble" "${HOMEBREW_LIB}/test/support/fixtures/babble" 2>/dev/null || true
  exit "${exit_code}"
}
trap cleanup EXIT INT TERM

cat >&2 <<'WARNING'
╔══════════════════════════════════════════════════════════════════════╗
║  WARNING: brew tap tests are about to run.                           ║
║                                                                      ║
║  Command and spec files will be temporarily hardlinked into:         ║
║    $(brew --repo)/Library/Homebrew/cmd/                              ║
║    $(brew --repo)/Library/Homebrew/cmd/babble/                       ║
║    $(brew --repo)/Library/Homebrew/test/cmd/                         ║
║                                                                      ║
║  Do NOT run brew update, brew upgrade, brew update-reset, or any     ║
║  git operations inside the Homebrew repository until tests finish.   ║
║  Doing so may remove the hardlinks and cause tests to fail.          ║
╚══════════════════════════════════════════════════════════════════════╝
WARNING

# Check that source files exist.
for src in "${BABBLE_CMD_SRC}" "${BABBLE_SPEC_SRC}" "${VERSION_LIB_SRC}" "${FMT_LIB_SRC}" "${FMT_SPEC_SRC}" "${SH_LIB_SRC}" "${SH_SPEC_SRC}" "${AM_LIB_SRC}" "${AM_SPEC_SRC}" "${FIXTURE_SRC}"
do
  if [[ ! -f "${src}" ]]
  then
    echo "Error: source file not found: ${src}" >&2
    exit 1
  fi
done

# Hardlink files into the Homebrew repository, clobbering any existing copies
# from a previous run. Hardlinks are required because parallel_rspec calls
# File.stat on the spec path relative to HOMEBREW_LIBRARY_PATH; symlinks that
# point outside that tree fail with ENOENT.
echo "==> Hardlinking files into Homebrew repository..." >&2
mkdir -p "${HOMEBREW_LIB}/cmd/babble" "${HOMEBREW_LIB}/test/cmd/babble" "${HOMEBREW_LIB}/test/support/fixtures/babble"
pairs=(
  "${BABBLE_CMD_SRC}:${BABBLE_CMD_DST}"
  "${BABBLE_SPEC_SRC}:${BABBLE_SPEC_DST}"
  "${VERSION_LIB_SRC}:${VERSION_LIB_DST}"
  "${FMT_LIB_SRC}:${FMT_LIB_DST}"
  "${FMT_SPEC_SRC}:${FMT_SPEC_DST}"
  "${SH_LIB_SRC}:${SH_LIB_DST}"
  "${SH_SPEC_SRC}:${SH_SPEC_DST}"
  "${AM_LIB_SRC}:${AM_LIB_DST}"
  "${AM_SPEC_SRC}:${AM_SPEC_DST}"
  "${FIXTURE_SRC}:${FIXTURE_DST}"
)
for pair in "${pairs[@]}"
do
  src="${pair%%:*}"
  dst="${pair##*:}"
  [[ -e "${dst}" ]] && echo "==> (replacing existing ${dst##*/})" >&2
  ln -f "${src}" "${dst}"
done

only="${1:-}"
if [[ -n "${only}" ]]
then
  echo "==> Running: brew tests ${only}" >&2
  brew tests "${only}"
else
  echo "==> Running: brew tests --only=cmd/babble" >&2
  brew tests --only=cmd/babble
  echo "==> Running: brew tests --only=cmd/babble/formatter" >&2
  brew tests --only=cmd/babble/formatter
  echo "==> Running: brew tests --only=cmd/babble/sh" >&2
  brew tests --only=cmd/babble/sh
  echo "==> Running: brew tests --only=cmd/babble/app_manager" >&2
  brew tests --only=cmd/babble/app_manager
fi

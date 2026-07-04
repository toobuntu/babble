#!/usr/bin/env bash

# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# Run brew typecheck with babble's tap files visible to Sorbet.
#
# `brew typecheck` only checks $(brew --repo)/Library/Homebrew, so a plain run
# never sees the tap's cmd/ files and passes vacuously. This script hardlinks
# cmd/babble.rb and the cmd/babble/ subtree into the brew repo (the same
# pattern as scripts/run-tests.sh; hardlinks so require_relative resolves
# inside the Homebrew tree), runs brew typecheck, then unlinks on exit.
#
# Specs are not linked: spec files are never `typed: strict` and brew's
# sorbet config does not cover test/.
#
# The same concurrency caveat as run-tests.sh applies: do NOT run brew
# update / upgrade / update-reset while this script is active.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TAP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

BREW_REPO="$(brew --repo)"
HOMEBREW_LIB="${BREW_REPO}/Library/Homebrew"

BABBLE_CMD_SRC="${TAP_DIR}/cmd/babble.rb"
BABBLE_CMD_DST="${HOMEBREW_LIB}/cmd/babble.rb"

VERSION_LIB_SRC="${TAP_DIR}/cmd/babble/version.rb"
VERSION_LIB_DST="${HOMEBREW_LIB}/cmd/babble/version.rb"

FMT_LIB_SRC="${TAP_DIR}/cmd/babble/formatter.rb"
FMT_LIB_DST="${HOMEBREW_LIB}/cmd/babble/formatter.rb"

cleanup() {
  local exit_code=$?
  echo "==> Removing hardlinks from Homebrew repository..." >&2
  rm -f "${BABBLE_CMD_DST}" "${VERSION_LIB_DST}" "${FMT_LIB_DST}"
  rmdir "${HOMEBREW_LIB}/cmd/babble" 2>/dev/null || true
  exit "${exit_code}"
}
trap cleanup EXIT INT TERM

for src in "${BABBLE_CMD_SRC}" "${VERSION_LIB_SRC}" "${FMT_LIB_SRC}"
do
  if [[ ! -f "${src}" ]]
  then
    echo "Error: source file not found: ${src}" >&2
    exit 1
  fi
done

echo "==> Hardlinking cmd files into Homebrew repository..." >&2
mkdir -p "${HOMEBREW_LIB}/cmd/babble"
ln -f "${BABBLE_CMD_SRC}" "${BABBLE_CMD_DST}"
ln -f "${VERSION_LIB_SRC}" "${VERSION_LIB_DST}"
ln -f "${FMT_LIB_SRC}" "${FMT_LIB_DST}"

echo "==> Running: brew typecheck" >&2
brew typecheck

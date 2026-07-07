# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: strict
# frozen_string_literal: true

# Babble's top-level namespace: supporting classes for the `brew babble`
# external command live here, not under Homebrew::Cmd (brew's tap command
# discovery only scans cmd/*.rb, so cmd/babble/*.rb files do not become
# phantom commands) and not under Homebrew::Babble (a top-level module
# cannot shadow brew-internal constants the way Homebrew::Cask would).
module Babble
  VERSION = T.let("0.6.0.pre", String)
end

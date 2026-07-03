# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: strict
# frozen_string_literal: true

require "abstract_command"
require_relative "babble/version"
require_relative "babble/formatter"

module Homebrew
  module Cmd
    # An interactive upgrade routine for Homebrew, Mac App Store, and macOS
    # software. Stub while the ksh-to-external-command migration is in
    # progress: argument parsing and the ⨀ banner land here; the upgrade
    # phases land in the C-blocks (see docs/handoff.md).
    class Babble < AbstractCommand
      cmd_args do
        description <<~EOS
          An interactive upgrade routine for Homebrew, Mac App Store, and macOS software.
        EOS

        switch "--no-update",
               description: "Skip the `brew update` phase."
        switch "--dry-run",
               description: "Print what would be upgraded without doing it."

        named_args :none
      end

      sig { override.void }
      def run
        raise UsageError, "`brew babble` is only supported on macOS." unless OS.mac?

        ::Babble::Formatter.oh1 "Babble #{::Babble::VERSION}"
        ::Babble::Formatter.ohai "Migration in progress; upgrade phases land in the C-blocks."
      end
    end
  end
end

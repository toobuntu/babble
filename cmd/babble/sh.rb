# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: strict
# frozen_string_literal: true

require "system_command"

module Babble
  # Thin shell-out wrapper over Homebrew's SystemCommand: one place to
  # capture stdout/stderr/exit status without raising on failure, so
  # callers can decide how to degrade. Grows only as C-blocks need it.
  module Sh
    # Result of a captured command. status is the exit status; a nil
    # exit (killed by signal) is reported as 1.
    class Result < T::Struct
      const :stdout, String
      const :stderr, String
      const :status, Integer

      sig { returns(T::Boolean) }
      def success? = status.zero?
    end

    class << self
      include SystemCommand::Mixin

      sig { params(executable: String, args: String).returns(Result) }
      def capture(executable, *args)
        result = system_command(executable,
                                args:         args,
                                print_stderr: false,
                                must_succeed: false)
        Result.new(stdout: result.stdout, stderr: result.stderr,
                   status: result.exit_status || 1)
      end
    end
  end
end

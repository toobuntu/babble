# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: strict
# frozen_string_literal: true

require "utils/output"

module Babble
  # Single home of babble's ⨀ output convention (ADR 0002): Homebrew's
  # oh1/ohai/opoo/ofail helpers with the message text prefixed by ⨀,
  # producing e.g. `==> ⨀ Babble message` — visually distinct from
  # Homebrew's own `==> …` lines. Severity colors, TTY detection, and
  # HOMEBREW_NO_COLOR handling all come from the Homebrew helpers; never
  # hardcode the prefix at call sites.
  module Formatter
    PREFIX = T.let("⨀", String)

    class << self
      include Utils::Output::Mixin

      sig { params(message: String).void }
      def oh1(message)
        super("#{PREFIX} #{message}")
      end

      sig { params(message: String, sput: T.anything).void }
      def ohai(message, *sput)
        super("#{PREFIX} #{message}", *sput)
      end

      sig { params(message: String).void }
      def opoo(message)
        super("#{PREFIX} #{message}")
      end

      sig { params(message: String).void }
      def ofail(message)
        super("#{PREFIX} #{message}")
      end
    end
  end
end

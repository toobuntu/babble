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

      # Sigs mirror Utils::Output::Mixin's exactly: sorbet-runtime
      # enforces override compatibility (contravariant params, matching
      # kwargs) when these redefine the mixin's methods.
      sig { params(message: String, truncate: T.any(Symbol, T::Boolean)).void }
      def oh1(message, truncate: :auto)
        super("#{PREFIX} #{message}", truncate:)
      end

      sig { params(message: T.any(String, Exception), sput: T.anything).void }
      def ohai(message, *sput)
        super("#{PREFIX} #{message}", *sput)
      end

      sig { params(message: T.any(String, Exception)).void }
      def opoo(message)
        super("#{PREFIX} #{message}")
      end

      sig { params(message: T.any(String, Exception)).void }
      def ofail(message)
        super("#{PREFIX} #{message}")
      end
    end
  end
end

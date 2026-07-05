# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: strict
# frozen_string_literal: true

require_relative "formatter"
require_relative "sh"

module Babble
  # App-lifecycle manager: knows which GUI apps are running and (in later
  # C-blocks) quits and reopens them around upgrades. State-bearing per the
  # W3 classification: holds the config reference and, later, cached
  # running-app snapshots.
  class AppManager
    # config: stays T.untyped until Babble::Config lands (C.2+).
    sig { params(config: T.untyped).void }
    def initialize(config:)
      @config = config
    end

    # Bundle ids of currently running GUI apps, de-duplicated and sorted.
    # Parses `/usr/bin/lsappinfo list`, whose per-app records carry
    # `bundleID="com.example.App"` lines (P0.3: the prototype matched
    # CFBundleIdentifier, which lsappinfo never emits, silently disabling
    # the entire app-lifecycle feature). Returns [] with a warning when
    # lsappinfo fails (e.g. no GUI session).
    sig { returns(T::Array[String]) }
    def running_bundle_ids
      result = Sh.capture("/usr/bin/lsappinfo", "list")
      unless result.success?
        Formatter.opoo "lsappinfo list failed (exit #{result.status}); " \
                       "treating no apps as running."
        return []
      end

      result.stdout.each_line
            .filter_map { |line| line[/^\s*bundleID="(.+?)"/, 1] }
            .uniq.sort
    end

    sig { params(bundle_id: String).void }
    def quit_app(bundle_id)
      raise NotImplementedError, "quit_app lands with the quit/reopen C-block"
    end

    sig { params(bundle_id: String).void }
    def reopen_app(bundle_id)
      raise NotImplementedError, "reopen_app lands with the quit/reopen C-block"
    end
  end
end

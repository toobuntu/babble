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

    # A syntactically plausible bundle id: alphanumerics, dots, hyphens
    # (refactor/modular's validator, confirmed against a real 134-id
    # lsappinfo capture). Anything else in a bundleID="…" line is logged
    # and excluded rather than fed to later quit/reopen phases.
    VALID_BUNDLE_ID = T.let(/\A[[:alnum:].-]+\z/i, Regexp)

    # Bundle ids of currently running GUI apps, validated, de-duplicated,
    # and sorted. Parses `/usr/bin/lsappinfo list`, whose per-app records
    # carry `bundleID="com.example.App"` lines. Ported from
    # refactor/modular's RunningGUIBundleIDs (the year-plus migration
    # worktree; see stash/code-archive/refactor-modular/refactor/ruby/
    # lib/utils/running_gui_bundle_ids.rb) — pattern, validation, and
    # error handling — reshaped onto Babble::Sh and Babble::Formatter.
    # P0.3 context: PR #1's Copilot prototype instead matched
    # CFBundleIdentifier, which lsappinfo never emits, silently disabling
    # the entire app-lifecycle feature; refactor/modular had it right.
    # Returns [] with a warning when lsappinfo fails (e.g. no GUI
    # session).
    sig { returns(T::Array[String]) }
    def running_bundle_ids
      result = Sh.capture("/usr/bin/lsappinfo", "list")
      unless result.success?
        Formatter.opoo "lsappinfo list failed (exit #{result.status}): " \
                       "#{result.stderr.strip}; treating no apps as running."
        return []
      end

      result.stdout.each_line
            .filter_map { |line| line[/^\s*bundleID="(.+?)"/, 1] }
            .filter_map do |id|
              next id if id.match?(VALID_BUNDLE_ID)

              Formatter.opoo "Ignoring invalid bundleID from lsappinfo: #{id.inspect}"
              nil
            end
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

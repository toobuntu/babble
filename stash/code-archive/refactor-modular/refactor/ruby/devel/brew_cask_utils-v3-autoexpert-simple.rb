# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# scripts/simple_quarantine_purger.rb

# frozen_string_literal: true
# typed: strict

require "pathname"

##
# SimpleQuarantinePurger removes Apple's Gatekeeper-related extended attributes
# (`com.apple.quarantine` and `com.apple.provenance`) recursively from a Homebrew
# Cask installation. This replicates the result of `--no-quarantine` post-install.
#
# Usage:
#   SimpleQuarantinePurger.run("firefox", debug: true)
#
# CLI:
#   ruby scripts/simple_quarantine_purger.rb firefox --debug
#
class SimpleQuarantinePurger
  class << self
    # Run the purge and validation for the given Cask token
    def run(token, debug: false)
      root = File.join(caskroom_path, token)
      unless Dir.exist?(root)
        warn "❌ No such Cask token directory: #{root}"
        return
      end

      log_debug("🔍 Sanitizing token=#{token} root=#{root}", debug)

      purge_xattrs(root, debug)
      validate_xattrs_removed(root, debug)
    end

    private

    def log_debug(msg, enabled)
      warn "[DEBUG] #{msg}" if enabled
    end

    def caskroom_path
      @caskroom_path ||= begin
        brew = ENV["HOMEBREW_BREW_FILE"] || `command -v brew`.strip
        raise "Homebrew not found in $PATH" if brew.empty?

        path = `#{brew} --caskroom`.strip
        raise "Unable to get caskroom path" if path.empty?

        path
      end
    end

    def purge_xattrs(path, debug)
      log_debug("🧹 Purging xattrs recursively from: #{path}", debug)

      system("/usr/bin/xattr", "-d", "-r", "com.apple.quarantine", path)
      system("/usr/bin/xattr", "-d", "-r", "com.apple.provenance", path)
    end

    def validate_xattrs_removed(path, debug)
      remaining = `xattr -r #{path}`.lines

      quarantine_still = remaining.grep(/com\.apple\.quarantine/)
      provenance_still = remaining.grep(/com\.apple\.provenance/)

      if quarantine_still.empty? && provenance_still.empty?
        puts "✅ No quarantine-related extended attributes remain."
      else
        warn "❌ Quarantine attributes still present:"
        warn quarantine_still unless quarantine_still.empty?
        warn provenance_still unless provenance_still.empty?
      end

      log_debug("Remaining xattrs:\n#{remaining.join}", debug) unless remaining.empty?
    end
  end
end

# Allow command-line usage but don't interfere with library use
if __FILE__ == $PROGRAM_NAME
  token = ARGV.find { |arg| !arg.start_with?("--") }
  debug = ARGV.include?("--debug")

  unless token
    warn "Usage: ruby simple_quarantine_purger.rb [--debug] <cask-token>"
    exit 1
  end

  SimpleQuarantinePurger.run(token, debug: debug)
end

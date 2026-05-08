# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# lib/brew_quarantine_manager.rb

# frozen_string_literal: true
# typed: strict

require "pathname"
require "json"
require "optparse"

##
# BrewQuarantineManager removes Apple's Gatekeeper quarantine-related
# extended attributes from Homebrew Casks after installation.
#
# This simulates the effect of `--no-quarantine` but applies after
# the fact to a fully extracted Caskroom directory.
#
# When dealing with multiple casks, relying on staged_path eliminates the need to deduce or validate appdir for each cask. This streamlines the logic, especially because the appdir is user-configurable. staged_path refers to the path within the Caskroom (e.g., $(brew --caskroom)/<token>/<version>), which is a symlink pointing to the appdir. Removing the com.apple.quarantine attribute at either staged_path or appdir achieves the same result because the symlink ensures they reference the same file system object. Modifying extended attributes like xattr on a symlink (e.g., staged_path) applies to the actual target file or directory (appdir/<name>.app).
#
# Usage (as a library):
#   BrewQuarantineManager.release_cask!("firefox", debug: true)
#
# Usage (as a CLI tool):
#   ruby brew_quarantine_manager.rb --cask firefox --debug
#
class BrewQuarantineManager
  class << self
    def release_cask!(token, debug: false)
      caskroom_path = `brew --caskroom #{token}`.strip
      unless Dir.exist?(caskroom_path)
        warn "❌ No such Caskroom path for token #{token}: #{caskroom_path}"
        return
      end

      log_debug("caskroom_path=#{caskroom_path}", debug)
      release_xattrs!(caskroom_path, debug)
    end

    private

    def log_debug(msg, enabled)
      warn "[DEBUG] #{msg}" if enabled
    end

    def release_xattrs!(path, debug)
      puts "#{path} is queued for release from quarantine"
      system("/usr/bin/xattr", "-d", "-r", "com.apple.quarantine", path)
      system("/usr/bin/xattr", "-d", "-r", "com.apple.provenance", path)

      validate_xattrs_removed(path, debug)
    end

    def validate_xattrs_removed(path, debug)
      remaining = `/usr/bin/xattr -r #{path}`.lines
      quarantine = remaining.grep(/com\.apple\.quarantine/)
      provenance = remaining.grep(/com\.apple\.provenance/)

      if quarantine.empty? && provenance.empty?
        puts "✅ #{path} is released from quarantine"
      else
        warn "❌ Quarantine-related extended attributes still present in #{path}:"
        warn quarantine unless quarantine.empty?
        warn provenance unless provenance.empty?
      end

      log_debug("Remaining xattrs:\n#{remaining.join}", debug) unless remaining.empty?
    end
  end
end

# CLI entrypoint
if __FILE__ == $PROGRAM_NAME
  options = { debug: false }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby brew_quarantine_manager.rb --cask TOKEN [options]"

    opts.on("--cask TOKEN", "Release quarantine from Cask by token") do |token|
      options[:cask] = token
    end

    opts.on("--debug", "Enable debug output") do
      options[:debug] = true
    end

    opts.on("-h", "--help", "Show help") do
      puts opts
      exit
    end
  end

  begin
    parser.parse!
  rescue OptionParser::InvalidOption => e
    warn "❌ #{e.message}"
    puts parser
    exit 1
  end

  if options[:cask]
    BrewQuarantineManager.release_cask!(options[:cask], debug: options[:debug])
  else
    warn "❌ Must provide --cask TOKEN"
    puts parser
    exit 1
  end
end

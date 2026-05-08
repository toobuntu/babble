# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# lib/brew_unquarantine.rb

# frozen_string_literal: true
# typed: strict

require "pathname"
require "json"
require "optparse"

##
# BrewUnquarantine removes Apple's Gatekeeper quarantine-related
# extended attributes from Homebrew Casks post-installation.
#
# It mimics the effect of `--no-quarantine`, operating on the extracted
# Caskroom directory of a given Cask token.
#
# Usage:
#   ruby brew_unquarantine.rb <cask-token> [--debug]
#   ruby brew_unquarantine.rb <cask-token> --status
#
class BrewUnquarantine
  XATTR = "/usr/bin/xattr"

  class << self
    def run(token, debug: false, status_only: false)
      caskroom_path = `brew --caskroom #{token}`.strip
      raise "No such Caskroom path for token #{token}: #{caskroom_path}" unless Dir.exist?(caskroom_path)

      if status_only
        detect(caskroom_path, debug: debug, status_only: status_only)
        return
      end

      return unless detect(caskroom_path, debug: debug, status_only: false)

      $stderr.puts "Releasing #{caskroom_path} from quarantine"
      system(XATTR, "-d", "-r", "com.apple.quarantine", caskroom_path)
      system(XATTR, "-d", "-r", "com.apple.provenance", caskroom_path)
      validate_xattrs_removed(caskroom_path, debug)
    end

    private

    def log_debug(msg, enabled)
      $stderr.puts "[DEBUG] #{msg}" if enabled
    end

    def detect(path, debug: false, status_only: false)
      $stderr.puts "Verifying Gatekeeper status of #{path}" if debug
      quarantine_status = status(path)
      is_quarantined = !quarantine_status.empty?
      msg = is_quarantined ? "#{path} is quarantined" : "#{path} is not quarantined"
      $stderr.puts msg if debug || status_only
      is_quarantined
    end

    def status(path)
      `#{XATTR} -p com.apple.quarantine "#{path}" 2>/dev/null`.strip
    end

    def validate_xattrs_removed(path, debug)
      remaining = `#{XATTR} -r #{path}`.lines
      quarantine = remaining.grep(/com\\.apple\\.quarantine/)
      provenance = remaining.grep(/com\\.apple\\.provenance/)

      if quarantine.empty? && provenance.empty?
        $stderr.puts "Successfully released #{path} from quarantine"
      else
        warn "❌ Attributes still present in #{path}:"
        warn quarantine unless quarantine.empty?
        warn provenance unless provenance.empty?
      end

      log_debug("Remaining xattrs:\n#{remaining.join}", debug) unless remaining.empty?
    end
  end
end

# CLI entrypoint
if __FILE__ == $PROGRAM_NAME
  options = { debug: false, status_only: false }

  parser = OptionParser.new do |opts|
    opts.banner = "Usage: ruby brew_unquarantine.rb [options] <cask-token>"

    opts.on("--debug", "Enable debug output") do
      options[:debug] = true
    end

    opts.on("--status", "Check quarantine status only (no changes made)") do
      options[:status_only] = true
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

  token = ARGV.shift
  unless token
    warn "❌ Missing Cask token"
    puts parser
    exit 1
  end

  BrewUnquarantine.run(token, debug: options[:debug], status_only: options[:status_only])
end

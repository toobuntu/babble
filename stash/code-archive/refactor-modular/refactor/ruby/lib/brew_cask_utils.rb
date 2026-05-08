# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: strict
# frozen_string_literal: true

# scripts/quarantine_purger.rb

require "find"
require "pathname"

# QuarantinePurger identifies `.app` bundles inside Homebrew's Caskroom,
# verifies that they're real application bundles, and removes Apple's extended
# attributes that might restrict execution (like quarantine or provenance).
#
# It replicates the functionality of a shell pipeline involving `find`,
# `readlink`, and `xattr`, but in a safe and portable Ruby class.
class QuarantinePurger
  class << self
    attr_accessor :debug
    attr_reader :token

    def initialize
      # Check if --debug is present in ARGV
      $stderr.puts "ARGV: #{ARGV.inspect}"
      @debug = ARGV.include?("--debug")

      # Remove --debug from ARGV to avoid interference
      ARGV.delete("--debug")

      # Assign the token after processing --debug
      @token = ARGV[0]
    end

    def run(token, debug_flag)
      @debug = debug_flag
      log_debug("token=#{token}")
      caskroom = caskroom_path
      log_debug("caskroom=#{caskroom}")
      root = File.join(caskroom, token)
      log_debug("root=#{root}")
      unless Dir.exist?(root)
        warn "No such cask directory: #{root}"
        return
      end

      app_candidates(root).each do |original|
        log_debug("[run] Resolving path of #{original}...")
        resolved = resolve_path(original)
        next unless resolved

        log_debug("resolved path=#{resolved}")
        next unless valid_app_bundle?(resolved)

        $stderr.puts "Starting Gatekeeper quarantine removal from: #{resolved}"
        purge_xattrs(resolved)
      end
    end

    private

    def log_debug(message)
      $stderr.puts("[DEBUG] #{message}").to_s if @debug
    end

    def find_brew
      ENV["HOMEBREW_BREW_FILE"] || `command -v brew`.strip
    end

    # Returns the base Caskroom path via `brew --caskroom`
    def caskroom_path
      @caskroom_path ||= begin
        brew = find_brew
        # The activesupport gem is not available
        # rubocop:disable Homebrew/Blank
        raise "Homebrew not found in $PATH" if brew.nil? || brew.empty?
        # rubocop:enable Homebrew/Blank

        log_debug("brew=#{brew}")

        path = `#{brew} --caskroom`.strip
        raise "Failed to determine Caskroom path from `brew --caskroom`" if path.empty?

        log_debug("path=#{path}")
        path
      end
    end

    # Finds .app files 2 levels deep in the caskroom token directory
    def app_candidates(base)
      Dir.glob("#{base}/*/*.app", File::FNM_CASEFOLD).select do |path|
        File.symlink?(path) || File.directory?(path)
      end
    end

    # Converts symlink to absolute path (like readlink -f)
    def resolve_path(path)
      log_debug("[resolve_path] Resolving path of #{path}...")
      Pathname.new(path).realpath.to_s
    rescue
      nil
    end

    # Checks for Contents/Info.plist inside the resolved bundle
    def valid_app_bundle?(resolved)
      log_debug("Validating #{resolved}...")
      dir = File.directory?(resolved)
      log_debug("#{resolved} is a directory...") if dir
      bundle = File.file?(File.join(resolved, "Contents", "Info.plist"))
      log_debug("#{resolved} is a valid app bundle...") if bundle
      bundle
    end

    # Removes both xattrs used by Apple security systems
    def purge_xattrs(path)
      log_debug("[purge_xattrs] Checking existing extended attributes for: #{path}...")

      # List current xattrs for the file
      existing_xattrs = `xattr -l #{path}`.split("\n")
      had_quarantine = existing_xattrs.any? { |attr| attr.include?("com.apple.quarantine") }
      had_provenance = existing_xattrs.any? { |attr| attr.include?("com.apple.provenance") }

      if !had_quarantine && !had_provenance
        $stderr.puts("No relevant Gatekeeper attributes found on: #{path}") unless @debug
        $stderr.puts("[purge_xattrs] No relevant Gatekeeper attributes found on: #{path}") if @debug
        return true # Nothing to remove, so we're "successful"
      end

      # Attempt to remove attributes
      log_debug("[purge_xattrs] Attempting to remove attributes from: #{path}...")
      system("/usr/bin/xattr", "-d", "-r", "com.apple.provenance", path)
      system("/usr/bin/xattr", "-d", "-r", "com.apple.quarantine", path)

      # Check attributes after removal
      remaining_xattrs = `xattr -l #{path}`.split("\n")
      still_has_quarantine = remaining_xattrs.any? { |attr| attr.include?("com.apple.quarantine") }
      still_has_provenance = remaining_xattrs.any? { |attr| attr.include?("com.apple.provenance") }

      if !still_has_quarantine && !still_has_provenance
        $stderr.puts("[purge_xattrs] Successfully removed Gatekeeper attributes from: #{path}")
        true
      else
        warn "[purge_xattrs] Failed to remove all Gatekeeper attributes from: #{path}"
        false
      end
    end
  end
end

# Command-line execution entrypoint
if __FILE__ == $PROGRAM_NAME
  # Detect the presence of --debug in ARGV and set @debug accordingly
  debug = ARGV.include?("--debug")

  # Remove --debug from ARGV to avoid interference with the token assignment
  ARGV.delete("--debug") if debug

  # Determine the token
  token = ENV["token"] || ARGV[0] || begin
    warn "Usage: ruby quarantine_purger.rb [--debug] <cask-token>"
    exit 1
  end

  QuarantinePurger.run(token, debug)
  $stderr.puts("Debug mode is #{debug ? "enabled" : "disabled"}.").to_s if debug
end

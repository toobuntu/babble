# typed: strict
# frozen_string_literal: true

require "find"
require "pathname"
require "open3"

module Babble
  class QuarantinePurger
    class << self
      def run(token, debug: false)
        @debug = debug
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
        $stderr.puts("[DEBUG] #{message}") if @debug
      end

      def find_brew
        ENV["HOMEBREW_BREW_FILE"] || `command -v brew`.strip
      end

      def caskroom_path
        @caskroom_path ||= begin
          brew = find_brew
          raise "Homebrew not found in $PATH" if brew.nil? || brew.empty?

          log_debug("brew=#{brew}")

          path = `#{brew} --caskroom`.strip
          raise "Failed to determine Caskroom path from `brew --caskroom`" if path.empty?

          log_debug("caskroom_path=#{path}")
          path
        end
      end

      def app_candidates(root)
        candidates = []
        Find.find(root) do |path|
          candidates << path if path.end_with?(".app")
        end
        candidates
      end

      def resolve_path(path)
        Pathname.new(path).realpath.to_s
      rescue SystemCallError => e
        log_debug("Failed to resolve #{path}: #{e.message}")
        nil
      end

      def valid_app_bundle?(path)
        return false unless File.directory?(path)
        return false unless path.end_with?(".app")

        contents = File.join(path, "Contents")
        return false unless File.directory?(contents)

        info_plist = File.join(contents, "Info.plist")
        File.exist?(info_plist)
      end

      def purge_xattrs(bundle_path)
        xattrs_to_remove = %w[
          com.apple.quarantine
          com.apple.provenance
        ]

        xattrs_to_remove.each do |xattr|
          remove_xattr_recursive(bundle_path, xattr)
        end
      end

      def remove_xattr_recursive(path, xattr)
        stdout, stderr, status = Open3.capture3(
          "xattr", "-dr", xattr, path
        )

        if status.success?
          $stderr.puts "Removed #{xattr} from #{path}"
        elsif !stderr.include?("No such xattr")
          $stderr.puts "Warning: Failed to remove #{xattr} from #{path}: #{stderr}"
        end
      end
    end
  end
end

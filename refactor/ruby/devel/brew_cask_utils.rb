# typed: strict
# frozen_string_literal: true

require "fileutils"
require "find"

module BrewCaskUtils
  # Provides utilities for managing Homebrew Cask applications, including
  # resolving installation paths and removing Gatekeeper quarantine attributes.
  #
  # @example Basic usage
  #   remover = BrewCaskUtils::GatekeeperQuarantineRemover.new('your-cask-name')
  #   remover.run
  #
  # @attr_reader [String] token The Homebrew Cask token/name
  # @attr_reader [Array<String>] app_paths List of resolved application paths
  class GatekeeperQuarantineRemover
    # @!attribute [r] token
    #   @return [String] Homebrew Cask token/name
    attr_reader :token

    # @!attribute [r] app_paths
    #   @return [Array<String>] List of validated application paths
    attr_reader :app_paths

    XATTR_ATTRIBUTES = %w[com.apple.provenance com.apple.quarantine].freeze

    # Initializes a new instance for a specific Homebrew Cask
    # @param token [String] The Homebrew Cask token/name
    def initialize(token)
      @token = token
      @caskroom_path = `brew --caskroom`.chomp
      @app_paths = []
    end

    # Resolves valid application paths for the Cask
    # @return [Array<String>] List of absolute paths to application bundles
    def resolve_app_paths
      cask_dir = File.join(@caskroom_path, @token)
      return [] unless File.directory?(cask_dir)

      Find.find(cask_dir) do |path|
        # Limit search depth to 2 levels (version directories)
        Find.prune if path.scan("/").size - cask_dir.scan("/").size > 1

        next unless valid_app_candidate?(path)

        resolved_path = resolve_symlink(path)
        @app_paths << resolved_path if valid_app_bundle?(resolved_path)
      end

      @app_paths.uniq
    end

    # Removes quarantine attributes from specified paths
    # @param paths [Array<String>, nil] Specific paths to process, defaults to resolved apps
    def remove_attributes(paths = nil)
      targets = paths || resolve_app_paths
      targets.each do |app_path|
        XATTR_ATTRIBUTES.each do |attr|
          system("sudo", "xattr", "-d", "-r", attr, app_path, exception: true)
        end
      end
    end

    # Interactive execution flow with confirmation
    def run
      apps = resolve_app_paths
      puts "Found #{apps.size} application bundles:"
      apps.each { |path| puts "  #{path}" }

      return if apps.empty?

      print "\nRemove quarantine attributes? (y/N) "
      return if gets.chomp.downcase != "y"

      remove_attributes
      puts "Attributes removed successfully."
    end

    private

    def valid_app_candidate?(path)
      File.basename(path) =~ /\.app$/i &&
        (File.directory?(path) || File.symlink?(path))
    end

    def resolve_symlink(path)
      File.symlink?(path) ? File.realpath(path) : path
    end

    def valid_app_bundle?(path)
      File.directory?(path) &&
        File.exist?(File.join(path, "Contents", "Info.plist"))
    end
  end
end

# Example usage:
# require_relative "brew_cask_utils"
# remover = BrewCaskUtils::GatekeeperQuarantineRemover.new("pikachuexe-freetube")
# remover.run

# If the script is run directly, execute the run method
# if __FILE__ == $PROGRAM_NAME
#   if ARGV.empty?
#     puts "Usage: #{$PROGRAM_NAME} <cask_token>"
#     puts "Example: #{$PROGRAM_NAME} firefox"
#     exit 1
#   end
#
#   cask_token = ARGV.first
#   remover = BrewCaskUtils::GatekeeperQuarantineRemover.new(cask_token)
#   remover.run
# end

if __FILE__ == $PROGRAM_NAME
  key = ARGV.first || "pikachuexe-freetube"
  # key = ARGV[0] || "pikachuexe-freetube"
  remover = BrewCaskUtils::GatekeeperQuarantineRemover.new(key)
  remover.run
end

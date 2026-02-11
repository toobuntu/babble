# typed: strict
# frozen_string_literal: true

# lib/config/reorganizer.rb

require "English"

module Config
  # This class reorders a YAML configuration file using yq, ensuring
  # each mapping conforms to an explicit key order while removing keys
  # with null values.
  #
  # For apps.homebrew, the desired order is:
  #   "token", "bundle_ids", "unsafe_to_quit", "quit_message", "bypass_gatekeeper".
  #
  # For apps.mas, the desired order is:
  #   "app_id", "name", "bundle_ids", "unsafe_to_quit", "quit_message".
  #
  # It also sorts the apps.homebrew array by "token" and the apps.mas
  # array by "name", as well as the bundle_ids arrays.
  #
  # Example:
  #   Config::Reorganizer.run("./Bundlefile.yml")
  #
  class Reorganizer
    class << self
      # Public entry point. Validates the file_path and then calls reorder_file.
      #
      # @param file_path [String] the path of the file to reorder.
      # @return [void]
      def run(file_path)
        unless File.exist?(file_path)
          $stderr.puts "Skipping reordering: File not found at path #{file_path}"
          return
        end

        reorder_file(file_path)
      end

      private

      # Reorders the specified file in-place via yq.
      #
      # @param file_path [String] the path to the YAML file.
      # @return [void]
      def reorder_file(file_path)
        return unless File.exist?(file_path)
        unless yq_available?
          $stderr.puts "Skipping reordering: yq is not available in PATH."
          return
        end

        original = File.read(file_path)
        # Use a multiline yq expression (via a heredoc) for readability.
        expr = <<~YQ.strip
          .apps.homebrew |= map(
            {
              "token": .token,
              "bundle_ids": (.bundle_ids // []),
              "unsafe_to_quit": .unsafe_to_quit,
              "quit_message": .quit_message,
              "bypass_gatekeeper": .bypass_gatekeeper
            } | with_entries(select(.value != null))
          ) | .apps.homebrew |= sort_by(.token) |
          .apps.mas |= map(
            {
              "app_id": .app_id,
              "name": .name,
              "bundle_ids": (.bundle_ids // []),
              "unsafe_to_quit": .unsafe_to_quit,
              "quit_message": .quit_message
            } | with_entries(select(.value != null))
          ) | .apps.mas |= sort_by(.name) |
          (.apps.homebrew[].bundle_ids) |= sort |
          (.apps.mas[].bundle_ids) |= sort
        YQ

        system("yq", "--exit-status", "--inplace", "eval", expr, file_path)

        if $CHILD_STATUS.success?
          if original != File.read(file_path)
            $stderr.puts "Reordered file: #{file_path}"
          else
            $stderr.puts "No changes needed for file: #{file_path} (already ordered)."
          end
        end
      rescue => e
        $stderr.puts "Error reordering #{file_path}: #{e.message}"
      end

      # Checks if yq is available in PATH.
      #
      # @return [Boolean] true if yq is executable, false otherwise.
      def yq_available?
        ENV["PATH"].split(File::PATH_SEPARATOR).any? do |dir|
          File.executable?(File.join(dir, "yq"))
        end
      end
    end
  end
end

# Allow the script to run when executed
if __FILE__ == $PROGRAM_NAME
  puts
  puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")

  # Ensure exactly one argument is passed
  if ARGV.size != 1
    $stderr.puts "Error: Exactly one file path argument is required."
    exit(1)
  end

  file_path = ARGV.first

  # Validate the file path
  unless File.exist?(file_path)
    $stderr.puts "Error: File not found at path '#{file_path}'."
    exit(1)
  end

  # Call the main method with the file path
  Config::Reorganizer.run(file_path)

  puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
end

# copilot

# typed: strict
# frozen_string_literal: true

require "open3"

# This class fetches and processes the bundle IDs of running GUI applications
# on macOS. It handles system command execution, validates output, and provides
# sorted, unique bundle IDs. It can be run both programmatically and as a CLI tool.
class RunningGUIBundleIDs
  def self.run
    bundle_ids = fetch_running_apps
    if bundle_ids.any?
      puts bundle_ids
    else
      $stderr.puts "No valid bundle IDs were found."
    end
  end

  class << self
    private

    def fetch_running_apps
      stdout, stderr, status = Open3.capture3("/usr/bin/lsappinfo list")

      if status.success?
        process_bundle_ids(stdout)
      else
        handle_error(stderr, status.exitstatus)
      end
    end

    def process_bundle_ids(output)
      bundle_ids = Set.new
      output.each_line do |line|
        match = line[/^\s*bundleID="(.+?)"/, 1]
        if match
          if valid_bundle_id?(match)
            bundle_ids.add(match)
          else
            log_invalid_bundle_id(match)
          end
        end
      end
      bundle_ids.to_a.sort
    end

    def valid_bundle_id?(bundle_id)
      bundle_id.match?(/^[[:alnum:].-]+$/i)
    end

    def log_invalid_bundle_id(invalid_id)
      $stderr.puts "Invalid bundleID detected: '#{invalid_id}'"
    end

    def handle_error(stderr, exit_status)
      $stderr.puts "Error: Command failed with exit status #{exit_status}. Details: #{stderr}"
      []
    end
  end
end

# If the script is run directly, execute the `run` method
RunningGUIBundleIDs.run if __FILE__ == $PROGRAM_NAME

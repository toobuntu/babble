# typed: strict
# frozen_string_literal: true

require "open3"
require "set"

# This class fetches and processes the bundle IDs of running GUI applications
# on macOS. It handles system command execution, validates output, and provides
# sorted, unique bundle IDs. It can be run both programmatically and as a CLI tool.
class BundleIDFetcher
  def self.run
    bundle_ids = fetch_running_apps
    if bundle_ids.any?
      puts bundle_ids
    else
      $stderr.puts "No valid bundle IDs were found."
    end
  end

  def self.fetch_running_apps
    stdout, stderr, status = Open3.capture3("/usr/bin/lsappinfo list")

    if status.success?
      process_bundle_ids(stdout)
    else
      handle_error(stderr, status.exitstatus)
    end
  end

  def self.process_bundle_ids(output)
    bundle_ids = Set.new
    output.each_line do |line|
      match = line[/^\s*bundleID="(.+?)"/, 1] # Extract `bundleID` using regex
      if match && valid_bundle_id?(match)
        bundle_ids.add(match)
      else
        log_invalid_bundle_id(line, match)
      end
    end
    bundle_ids.to_a.sort
  end

  def self.valid_bundle_id?(bundle_id)
    # Validate `bundleID` format using a regex
    bundle_id.match?(/^[[:alnum:].-]+$/i)
  end

  def self.log_invalid_bundle_id(line, invalid_id)
    if invalid_id
      $stderr.puts "Invalid bundleID detected: '#{invalid_id}' in line: '#{line.strip}'"
    else
      $stderr.puts "No bundleID found in line: '#{line.strip}'"
    end
  end

  def self.handle_error(stderr, exit_status)
    $stderr.puts "Error: Command failed with exit status #{exit_status}. Details: #{stderr}"
    []
  end
end

# If the script is run directly, execute the `run` method
BundleIDFetcher.run if __FILE__ == $PROGRAM_NAME

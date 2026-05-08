#!/usr/bin/env ruby

# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: strict
# frozen_string_literal: true

require "English"
require "yaml"
require "open3"
require "json"

# BrewUpgrade
#
# The BrewUpgrade module automates the process of upgrading Homebrew
# formulae and casks. It provides methods for listing outdated packages,
# upgrading them, and managing related tasks. A key feature is the ability
# to read cask tokens and their associated Bundle IDs from a configuration
# file, automatically quitting those applications before the upgrade and
# reopening them once the upgrade is complete.
#
# Usage:
#   BrewUpgrade.upgrade_packages
#
module BrewUpgrade
  # Define potential locations for the config file
  CONFIG_FILE_LOCATIONS = [
    "./.#{config_file_basename}.yml",               # Current working directory (higher precedence)
    "#{Dir.home}/.#{config_file_basename}.yml",     # Home directory
    "#{Dir.home}/.config/#{program_name}/#{config_file_basename}.yml", # Config directory
    "/etc/#{config_file_basename}.yml"              # System directory (lower precedence)
  ]

  # Load and validate configuration files
  def self.load_configuration
    # 1. Find the configuration file(s)
    config = load_and_merge_config_files(CONFIG_FILE_LOCATIONS)

    # 2. Validate the configuration
    validate_configuration(config)

    config
  end

  def load_and_merge_config_files(locations)
    # Step 1: Find all config files
    possible_configs = find_config_files(locations)
    merged_config = {}

    possible_configs.each do |config_file|
      # Step 2: Load each config and merge
      raw_config = load_config(config_file)
      merged_config = deep_merge(merged_config, raw_config)
    end

    merged_config
  end

  # Find all config files in given locations
  def self.find_config_files(locations)
    locations.each_with_object([]) do |location, found_configs|
      path = File.expand_path(location)
      if File.exist?(path)
        found_configs << path
      end
    end
  end

  # Load a config file (YAML)
  def self.load_config(file_path)
    begin
      YAML.load_file(file_path)
    rescue => e
      $stderr.puts "Error loading config file: #{e.message}"
      {}
    end
  end

  # Deep merge two hash configurations
  def self.deep_merge(hash1, hash2)
    hash2.each_with_object(hash1.dup) do |(key, value), merged|
      if value.is_a?(Hash) && hash1[key].is_a?(Hash)
        merged[key] = deep_merge(hash1[key], value)
      else
        # Merge 'unsafe_quit' flag with precedence
        if key == :unsafe_quit
          merged[key] = value if value == true
        else
          merged[key] = value
        end
      end
    end
  end

  # Validate the configuration
  def self.validate_configuration(config)
    if config.empty?
      $stderr.puts "Warning: Configuration is empty or invalid!"
      return false
    end

    # Add additional validation logic as needed
    true
  end
===
  final_config = {}

  # Iterate through the possible locations in order of precedence
  possible_locations.each do |path|
    if File.exist?(path)
      begin
        # Load the configuration file
        raw_config = YAML.load_file(path)

        # Merge the loaded config into the final config, prioritizing the current file
        final_config = deep_merge(final_config, raw_config)
      rescue Psych::SyntaxError => e
        $stderr.puts "Warning: Failed to parse YAML configuration file at #{path}. #{e.message}"
      end
    end
  end

  final_config
end

# Merge method to stack hashes, prioritizing the second argument over the first
def deep_merge(hash1, hash2)
  hash2.each_with_object(hash1.dup) do |(key, value), merged|
    if value.is_a?(Hash) && hash1[key].is_a?(Hash)
      merged[key] = deep_merge(hash1[key], value)
    else
      # Merge 'unsafe_quit' flag with precedence
      if key == :unsafe_quit
        # Only set unsafe_quit if the value is true (true takes precedence)
        merged[key] = value if value == true
      else
        merged[key] = value
      end
    end
  end
end

end
===

  def find_config_file(config_file_name)
  # Define potential locations for the config file
  possible_locations = [
    "./.#{config_file_basename}.yml",               # Current working directory
    "#{Dir.home}/.#{config_file_basename}.yml",     # Home directory
    "#{Dir.home}/.config/#{program_name}/#{config_file_basename}.yml", # Config directory
    "/etc/#{config_file_basename}.yml"              # System directory
  ]

  # Check each location in order of precedence
  possible_locations.each do |path|
    return path if File.exist?(path)
  end

  nil # Return nil if no config file is found
end

program_name = "upgrade_manager"
config_file_name = "app-quit-reopen"
config_file_path = find_config_file(program_name)

if config_file_path
  puts "Configuration file found at: #{config_file_path}"
else
  puts "No configuration file found for #{program_name}."
end

  # CONFIG_FILE = '/path/to/your/config.yml'
  CONFIG_FILE = "rubytest-config.yml"

  # Check if yq is available on the system
  def self.yq_available?
    ENV["PATH"].split(File::PATH_SEPARATOR).any? do |directory|
      File.executable?(File.join(directory, "yq"))
    end
  end

  # Validate bundle ID according to Apple's specifications
  def self.valid_bundle_id?(bundle_id)
    bundle_id.match?(/^[[:alnum:].-]+$/i)
  end

  # Validate Homebrew token, including pinned versions and channels
  def self.valid_homebrew_token?(token)
    token.match?(/^[a-z0-9]+(-[a-z0-9]+)*(@[a-z0-9.-]+)?$/)
  end

  # Check if a token listed in the configuration file is installed
  def self.token_installed?(token)
    # Commented-out line split for clarity and adherence to style guidelines
    # system("brew list | grep --quiet --fixed-strings --ignore-case #{token}") ||
    # system("mas list | grep --quiet --fixed-strings --ignore-case #{token}")
    begin
      stdout, _, status = Open3.capture3("brew list")
      raise "brew list failed" unless status.success?

      if stdout.include?(token.to_s)
        $stderr.puts "[brew] #{token} is installed."
      else
        $stderr.puts "[brew] #{token} is not installed."
      end
    rescue => e
      $stderr.puts "An error occurred: #{e.message}"
      # $stderr.puts stderr unless stderr.strip.empty?
    end

    begin
      stdout, _, status = Open3.capture3("mas list")
      raise "mas list failed" unless status.success?

      if stdout.include?(token.to_s)
        $stderr.puts "[mas] #{token} is installed."
      else
        $stderr.puts "[mas] #{token} is not installed."
      end
    rescue => e
      $stderr.puts "An error occurred: #{e.message}"
      # $stderr.puts stderr unless stderr.strip.empty?
    end
  end

  # Test bundle ID validation
  def self.test_valid_bundle_id
    valid_cases = ["com.example.app", "com.example-app.sub", "COM.EXAMPLE.APP"]
    invalid_cases = ["com.example.app!", "com.example.app_sub", "com.example.app/sub"]

    valid_cases.each do |case_|
      raise "Failed for valid Bundle ID case: #{case_}" unless BrewUpgrade.valid_bundle_id?(case_)
    end

    invalid_cases.each do |case_|
      raise "Failed for invalid Bundle ID case: #{case_}" if BrewUpgrade.valid_bundle_id?(case_)
    end

    puts "All Bundle ID validation tests passed."
  end

  # Test Homebrew token validation
  def self.test_valid_homebrew_token
    valid_cases = ["example-token", "token", "token-with-hyphens", "token@1.2.3", "token@nightly"]
    invalid_cases = ["Token", "TOKEN", "token_with_underscore", "token@invalid!", "token@1.2@3", "-token", "token-",
                     "to__ken"]

    valid_cases.each do |case_|
      raise "Failed for valid Homebrew token case: #{case_}" unless BrewUpgrade.valid_homebrew_token?(case_)
    end

    invalid_cases.each do |case_|
      raise "Failed for invalid Homebrew token case: #{case_}" if BrewUpgrade.valid_homebrew_token?(case_)
    end

    puts "All Homebrew token validation tests passed."
  end

  # Validate and clean the configuration
  def self.validate_config(config)
    valid_config = {}
    conflicts = []
    validation_errors = []
    structural_issues = []

    config.each do |token, data|
      unless BrewUpgrade.valid_homebrew_token?(token)
        validation_errors << "Invalid Homebrew token: #{token}"
        next
      end

      if BrewUpgrade.token_installed?(token)
        data["bundle_ids"].each do |bundle_id|
          unless BrewUpgrade.valid_bundle_id?(bundle_id)
            $stderr.puts "Warning: Bundle ID #{bundle_id} is not currently installed but may be valid."
          end
        end
      else
        $stderr.puts "Warning: Token #{token} is not installed."
      end

      conflicts << "Duplicate entry for token: #{token}" if valid_config.key?(token)

      valid_data = valid_config[token] || { "bundle_ids" => [] }

      if data.is_a?(Hash)
        if data["bundle_ids"].is_a?(Array)
          valid_bundle_ids = data["bundle_ids"].select { |id| BrewUpgrade.valid_bundle_id?(id.to_s) }
          invalid_bundle_ids = data["bundle_ids"] - valid_bundle_ids
          validation_errors.concat(invalid_bundle_ids.map { |id| "Invalid Bundle ID for #{token}: #{id}" })
          valid_data["bundle_ids"].concat(valid_bundle_ids).uniq!(&:downcase)
        else
          structural_issues << "Missing or invalid 'bundle_ids' for #{token}"
        end

        if data.key?("unsafe_quit")
          if valid_data.key?("unsafe_quit") && valid_data["unsafe_quit"] != data["unsafe_quit"]
            conflicts << "Conflicting 'unsafe_quit' values for #{token}"
          end
          valid_data["unsafe_quit"] = [valid_data["unsafe_quit"], data["unsafe_quit"]].compact.any?
        end

        if data.key?("quit_message")
          if valid_data.key?("quit_message") && valid_data["quit_message"] != data["quit_message"]
            conflicts << "Conflicting 'quit_message' values for #{token}"
          end
          valid_data["quit_message"] = data["quit_message"].to_s
        end
      else
        structural_issues << "Invalid data structure for #{token}"
      end

      valid_config[token] = valid_data
    end

    [valid_config, conflicts, validation_errors, structural_issues]
  end

  def self.load_and_validate_configuration(config_file)
    raw_config = {}
    if File.exist?(config_file)
      begin
        raw_config = YAML.load_file(config_file)
      rescue Psych::SyntaxError => e
        $stderr.puts "Warning: Failed to parse YAML configuration file. #{e.message}"
        $stderr.puts "Proceeding with empty configuration."
      end
    end

    config, conflicts, validation_errors, structural_issues = BrewUpgrade.validate_config(raw_config)

    if config.empty?
      $stderr.puts "Warning: No valid entries found in the configuration file. Proceeding with default behavior."
    else
      unless validation_errors.empty?
        $stderr.puts "Validation Errors:"
        validation_errors.each { |error| $stderr.puts "  - #{error}" }
      end

      unless structural_issues.empty?
        $stderr.puts "Structural Issues:"
        structural_issues.each { |issue| $stderr.puts "  - #{issue}" }
      end

      unless conflicts.empty?
        $stderr.puts "Conflicts:"
        conflicts.each { |conflict| $stderr.puts "  - #{conflict}" }
        $stderr.puts "Conflicts have been resolved by merging entries and using conservative settings."
      end

      if validation_errors.empty? && structural_issues.empty? && conflicts.empty?
        $stderr.puts "Configuration loaded successfully with no issues."
      else
        $stderr.puts "Proceeding with validated and merged configuration."
      end
    end

    config
  end

  # Attempt to reorganize the configuration file for better readability
  # This function uses 'yq' if available to sort keys and bundle IDs
  def self.reorganize_config_file(file_path)
    return false unless File.exist?(file_path)

    if BrewUpgrade.yq_available?
      original_content = File.read(file_path)
      begin
        sorted_content = `yq eval 'sort_keys(..) | (.[] | .bundle_ids) |= sort' #{file_path}`
        if $CHILD_STATUS.success?
          if original_content == sorted_content
            $stderr.puts "Configuration file is already properly organized."
            false
          else
            File.write(file_path, sorted_content)
            $stderr.puts "Configuration file has been reorganized."
            true
          end
        else
          $stderr.puts "Error: yq command failed."
          false
        end
      rescue => e
        $stderr.puts "Error executing yq: #{e.message}"
        false
      end
    else
      $stderr.puts "Note: Install 'yq' for enhanced config file organization capabilities."
      false
    end
  end

  # def self.reorganize_config_file(file_path)
  #   return false unless File.exist?(file_path)
  #
  #   if BrewUpgrade.yq_available?
  #     original_content = File.read(file_path)
  #     sorted_content = `yq eval 'sort_keys(..) | (.[] | .bundle_ids) |= sort' #{file_path}`
  #
  #     if original_content != sorted_content
  #     if system("yq", "eval", 'sort_keys(..) | (.[] | .bundle_ids) |= sort', file_path, out: File::NULL) !=
  #     File.read(file_path)
  #       if system("yq", "--inplace", "eval", 'sort_keys(..) | (.[] | .bundle_ids) |= sort', file_path)
  #         STDERR.puts "Configuration file has been reorganized using yq."
  #       else
  #         STDERR.puts "Failed to reorganize configuration file."
  #         return false
  #       end
  #     else
  #       STDERR.puts "Configuration file is already properly organized."
  #       return true
  #     end
  #   else
  #     STDERR.puts "Note: Install 'yq' for enhanced config file organization capabilities."
  #     return true  # It is not a critical failure if yq is unavailable
  #   end
  # end

  # ENV['HOMEBREW_COLOR'] = '1'

  def self.display_outdated_packages
    # By default, version information is displayed in interactive shells, and suppressed otherwise.
    # Use --verbose to include detailed version information.
    cmd = "brew outdated --greedy-auto-updates --fetch-HEAD --verbose"
    stdout, status = Open3.capture2(cmd)

    if status.success?
      unless stdout.strip.empty?
        puts "Outdated packages:"
        puts stdout
      end
    else
      $stderr.puts "Error running brew outdated command."
    end
  end

  def self.outdated_casks_json
    cmd = "brew outdated --greedy-auto-updates --fetch-HEAD --json=v2"
    stdout, status = Open3.capture2(cmd)

    if status.success?
      begin
        json_data = JSON.parse(stdout)
        # Extract only cask tokens
        json_data["casks"].map { |c| c["name"] }
      rescue JSON::ParserError => e
        $stderr.puts "Error parsing JSON output from brew: #{e.message}"
        []
      end
    else
      $stderr.puts "Error running brew outdated command."
      []
    end
  end

  def self.set_running_apps
    # Get the list of running GUI apps and their bundle IDs using lsappinfo
    stdout, status = Open3.capture2(
      "/usr/bin/lsappinfo list | " \
      "/usr/bin/awk -F'\"' '/bundleID/{print $2}' | " \
      "/usr/bin/sort -u",
    )

    if status.success?
      stdout.split("\n").compact
    else
      $stderr.puts "Error getting running apps."
      []
    end
  end

  def self.quit_app(bundle_id, config_entry)
    if config_entry["unsafe_quit"]
      puts config_entry["quit_message"] || "Please save your work in the application before continuing."
      puts "Press Enter when ready to quit the application."
      gets
    end

    # JavaScript requires double quotes for string literals
    # Ruby requires double quotes for string interpolation
    jxa_script = <<-EOS
    var app;
    try {
        var app = Application("#{bundle_id}");
        if (app.running()) {
            app.quit();
            $.NSFileHandle.fileHandleWithStandardOutput.writeData(
                $.NSString.alloc.initWithUTF8String("Successfully quit application with Bundle ID: #{bundle_id}.\\n").dataUsingEncoding($.NSUTF8StringEncoding)
            );
        } else {
            $.NSFileHandle.fileHandleWithStandardError.writeData(
                $.NSString.alloc.initWithUTF8String("Application with Bundle ID: #{bundle_id} is not running.\\n").dataUsingEncoding($.NSUTF8StringEncoding)
            );
        }
    } catch (error) {
        // Handle error
        $.NSFileHandle.fileHandleWithStandardError.writeData(
            $.NSString.alloc.initWithUTF8String("Error while processing Bundle ID: #{bundle_id}. " + error.toString() + "\\n").dataUsingEncoding($.NSUTF8StringEncoding)
        );
    }
    // Avoid returning a value to suppress unwanted output
    // Explicitly suppress any additional output
    undefined;
    EOS

    # Print the final JXA script for debugging
    # STDERR.puts "JXA Script:"
    # STDERR.puts jxa_script

    # Execute the JXA script
    stdout, stderr, = Open3.capture3("osascript -l JavaScript", stdin_data: jxa_script)
    BrewUpgrade.handle_quit_result(stdout, stderr, bundle_id)
  end

  def self.handle_quit_result(stdout, stderr, bundle_id)
    # Debug output
    puts "stdout: #{stdout}"
    puts "stderr: #{stderr}"

    # Handle successful quit
    if stdout.include?("Successfully quit application")
      puts "Successfully quit application: #{bundle_id}"
      return true
    end

    # Handle app not running
    if stderr.include?("is not running")
      puts "Application #{bundle_id} was not running."
      return false
    end

    # Handle errors from stderr
    unless stderr.empty?
      $stderr.puts "Warning: Failed to quit application with Bundle ID #{bundle_id} - #{stderr.strip}"
      return false
    end

    # Handle unexpected output from stdout
    return if stdout.empty?

    $stderr.puts "Warning: Unexpected output while processing Bundle ID #{bundle_id} - #{stdout.strip}"
    false
  end

  # def self.handle_quit_result(stdout, stderr, bundle_id)
  #   if !stdout.strip.empty? && stdout.strip.include?("Successfully quit application")
  #     puts "Successfully quit application: #{bundle_id}"
  #     return true # Explicitly return to avoid further checks
  #   elsif !stderr.strip.empty? && stderr.strip.include?("is not running")
  #     puts "Application #{bundle_id} was not running."
  #     return false
  #   elsif !stderr.empty?
  #     $stderr.puts "Warning: Failed to quit application with Bundle ID #{bundle_id} - #{stderr.strip}"
  #     return false
  #   else
  #     $stderr.puts "Warning: Unexpected output while processing Bundle ID #{bundle_id} - #{stdout.strip}"
  #     return false
  #   end
  # end

  def self.open_app(bundle_id)
    success = system("/usr/bin/open", "-b", bundle_id)

    return if success

    $stderr.puts "Warning: Failed to open application with Bundle ID #{bundle_id}."
  end

  def self.upgrade_packages
    # Upgrade all outdated packages at once with specified options
    success = system("brew", "upgrade", "--greedy-auto-updates", "--fetch-HEAD", "--display-times")

    $stderr.puts "Warning: Failed to upgrade packages." unless success

    success # Return whether the upgrade was successful or not.
  end

  # Main logic
  begin
    # Run validation tests
    BrewUpgrade.test_valid_bundle_id
    BrewUpgrade.test_valid_homebrew_token

    # Attempt to reorganize the configuration file for better readability
    BrewUpgrade.reorganize_config_file(CONFIG_FILE)

    # Load and validate configuration
    config = BrewUpgrade.load_and_validate_configuration(CONFIG_FILE)

    # Display nicely formatted information about outdated packages
    BrewUpgrade.display_outdated_packages

    # Get outdated casks and running apps
    outdated_cask_tokens = BrewUpgrade.outdated_casks_json # Get structured data for processing.
    running_apps = BrewUpgrade.set_running_apps

    # Determine which casks need to be quit and reopened
    # prints if in config file even if no bundle id is running
    # casks_to_quit_and_reopen = config.keys.select { |token| outdated_cask_tokens.include?(token) }
    casks_to_quit_and_reopen = config.keys.select do |token|
      # Check if the cask is outdated and if any associated bundle IDs are running
      outdated_cask_tokens.include?(token) && config[token]["bundle_ids"].any? do |bundle_id|
        running_apps.include?(bundle_id)
      end
    end

    if casks_to_quit_and_reopen.any?
      puts "The following casks are scheduled for upgrade and will require quitting/reopening:\n  " \
           "#{casks_to_quit_and_reopen.join("\n  ")}"

      # Quit all associated apps if they are running (only for GUI apps)
      casks_to_quit_and_reopen.each do |cask_token|
        data = config[cask_token]

        data["bundle_ids"].each do |bundle_id|
          if running_apps.include?(bundle_id)
            puts "Quitting #{bundle_id}..."
            BrewUpgrade.quit_app(bundle_id, data)
          else
            $stderr.puts "#{bundle_id} is not running, skipping quit."
          end
        end
      end
    end

    # Upgrade all outdated packages regardless of whether they are in the config file or not.
    puts "Upgrading all outdated packages..."
    upgraded_successfully = BrewUpgrade.upgrade_packages

    # Reopen applications after upgrade (if they were previously running)
    if casks_to_quit_and_reopen.any?
      casks_to_quit_and_reopen.each do |cask_token|
        data = config[cask_token]

        data["bundle_ids"].each do |bundle_id|
          if running_apps.include?(bundle_id)
            puts "Reopening #{bundle_id}..."
            BrewUpgrade.open_app(bundle_id)
          else
            $stderr.puts "#{bundle_id} was not running, skipping reopen."
          end
        end
      end
    end

    # Final message based on whether any upgrades were performed.
    if upgraded_successfully || casks_to_quit_and_reopen.any?
      puts "Upgrade process complete."
    else
      puts "No upgrades were needed; everything is up to date."
    end
  rescue => e
    puts "Error: #{e.message}"
    exit 1
  end
end

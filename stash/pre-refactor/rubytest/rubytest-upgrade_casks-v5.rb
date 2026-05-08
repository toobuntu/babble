#!/usr/bin/env ruby

# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# frozen_string_literal: true

require 'yaml'
require 'open3'
require 'json'

# CONFIG_FILE = '/path/to/your/config.yml'
CONFIG_FILE = 'rubytest-config.yml'

# Check if yq is available on the system
def yq_available?
  ENV['PATH'].split(File::PATH_SEPARATOR).any? do |directory|
    File.executable?(File.join(directory, 'yq'))
  end
end

# Validate bundle ID according to Apple's specifications
def valid_bundle_id?(bundle_id)
  bundle_id.match?(/^[[:alnum:].-]+$/i)
end

# Validate Homebrew token, including pinned versions and channels
def valid_homebrew_token?(token)
  token.match?(/^[a-z0-9]+(-[a-z0-9]+)*(@[a-z0-9.-]+)?$/)
end

# Test bundle ID validation
def test_valid_bundle_id
  valid_cases = ['com.example.app', 'com.example-app.sub', 'COM.EXAMPLE.APP']
  invalid_cases = ['com.example.app!', 'com.example.app_sub', 'com.example.app/sub']

  valid_cases.each do |case_|
    raise "Failed for valid Bundle ID case: #{case_}" unless valid_bundle_id?(case_)
  end

  invalid_cases.each do |case_|
    raise "Failed for invalid Bundle ID case: #{case_}" if valid_bundle_id?(case_)
  end

  puts "All Bundle ID validation tests passed."
end

# Test Homebrew token validation
def test_valid_homebrew_token
  valid_cases = ['example-token', 'token', 'token-with-hyphens', 'token@1.2.3', 'token@nightly']
  invalid_cases = ['Token', 'TOKEN', 'token_with_underscore', 'token@invalid!', 'token@1.2@3', '-token', 'token-', 'to__ken']

  valid_cases.each do |case_|
    raise "Failed for valid Homebrew token case: #{case_}" unless valid_homebrew_token?(case_)
  end

  invalid_cases.each do |case_|
    raise "Failed for invalid Homebrew token case: #{case_}" if valid_homebrew_token?(case_)
  end

  puts "All Homebrew token validation tests passed."
end

# Validate and clean the configuration
def validate_config(config)
  valid_config = {}
  conflicts = []
  validation_errors = []
  structural_issues = []

  config.each do |token, data|
    unless valid_homebrew_token?(token)
      validation_errors << "Invalid Homebrew token: #{token}"
      next
    end

    if valid_config.key?(token)
      conflicts << "Duplicate entry for token: #{token}"
    end

    valid_data = valid_config[token] || { 'bundle_ids' => [] }

    if data.is_a?(Hash)
      if data['bundle_ids'].is_a?(Array)
        valid_bundle_ids = data['bundle_ids'].select { |id| valid_bundle_id?(id.to_s) }
        invalid_bundle_ids = data['bundle_ids'] - valid_bundle_ids
        validation_errors.concat(invalid_bundle_ids.map { |id| "Invalid Bundle ID for #{token}: #{id}" })
        valid_data['bundle_ids'].concat(valid_bundle_ids).uniq!(&:downcase)
      else
        structural_issues << "Missing or invalid 'bundle_ids' for #{token}"
      end

      if data.key?('unsafe_quit')
        if valid_data.key?('unsafe_quit') && valid_data['unsafe_quit'] != data['unsafe_quit']
          conflicts << "Conflicting 'unsafe_quit' values for #{token}"
        end
        valid_data['unsafe_quit'] = [valid_data['unsafe_quit'], data['unsafe_quit']].compact.any?
      end

      if data.key?('quit_message')
        if valid_data.key?('quit_message') && valid_data['quit_message'] != data['quit_message']
          conflicts << "Conflicting 'quit_message' values for #{token}"
        end
        valid_data['quit_message'] = data['quit_message'].to_s
      end
    else
      structural_issues << "Invalid data structure for #{token}"
    end

    valid_config[token] = valid_data
  end

  [valid_config, conflicts, validation_errors, structural_issues]
end

def load_and_validate_configuration(config_file)
  raw_config = {}
  if File.exist?(config_file)
    begin
      raw_config = YAML.load_file(config_file)
    rescue Psych::SyntaxError => e
      STDERR.puts "Warning: Failed to parse YAML configuration file. #{e.message}"
      STDERR.puts "Proceeding with empty configuration."
    end
  end

  config, conflicts, validation_errors, structural_issues = validate_config(raw_config)

  if config.empty?
    STDERR.puts "Warning: No valid entries found in the configuration file. Proceeding with default behavior."
  else
    if !validation_errors.empty?
      STDERR.puts "Validation Errors:"
      validation_errors.each { |error| STDERR.puts "  - #{error}" }
    end

    if !structural_issues.empty?
      STDERR.puts "Structural Issues:"
      structural_issues.each { |issue| STDERR.puts "  - #{issue}" }
    end

    if !conflicts.empty?
      STDERR.puts "Conflicts:"
      conflicts.each { |conflict| STDERR.puts "  - #{conflict}" }
      STDERR.puts "Conflicts have been resolved by merging entries and using conservative settings."
    end

    if validation_errors.empty? && structural_issues.empty? && conflicts.empty?
      STDERR.puts "Configuration loaded successfully with no issues."
    else
      STDERR.puts "Proceeding with validated and merged configuration."
    end
  end

  config
end

# Attempt to reorganize the configuration file for better readability
# This function uses 'yq' if available to sort keys and bundle IDs
def reorganize_config_file(file_path)
  return false unless File.exist?(file_path)

  if yq_available?
    original_content = File.read(file_path)
    begin
      sorted_content = %x(yq eval 'sort_keys(..) | (.[] | .bundle_ids) |= sort' #{file_path})
      if $?.success?
        if original_content != sorted_content
          File.write(file_path, sorted_content)
          STDERR.puts "Configuration file has been reorganized."
          return true
        else
          STDERR.puts "Configuration file is already properly organized."
          return false
        end
      else
        STDERR.puts "Error: yq command failed."
        return false
      end
    rescue => e
      STDERR.puts "Error executing yq: #{e.message}"
      return false
    end
  else
    STDERR.puts "Note: Install 'yq' for enhanced config file organization capabilities."
    return false
  end
end

# def reorganize_config_file(file_path)
#   return false unless File.exist?(file_path)
#
#   if yq_available?
#     original_content = File.read(file_path)
#     sorted_content = `yq eval 'sort_keys(..) | (.[] | .bundle_ids) |= sort' #{file_path}`
#
#     if original_content != sorted_content
#     if system("yq", "eval", 'sort_keys(..) | (.[] | .bundle_ids) |= sort', file_path, out: File::NULL) != File.read(file_path)
#       if system("yq", "--inplace", "eval", 'sort_keys(..) | (.[] | .bundle_ids) |= sort', file_path)
#         STDERR.puts "Configuration file has been reorganized using yq."
#         return true
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

def display_outdated_packages
  # By default, version information is displayed in interactive shells, and suppressed otherwise. Use --verbose to include detailed version information.
  cmd = "brew outdated --greedy-auto-updates --fetch-HEAD --verbose"
  stdout, status = Open3.capture2(cmd)

  if status.success?
    unless stdout.strip.empty?
      puts "Outdated packages:"
      puts stdout
    end
  else
    STDERR.puts "Error running brew outdated command."
  end
end

def get_outdated_casks_json
  cmd = "brew outdated --greedy-auto-updates --fetch-HEAD --json=v2"
  stdout, status = Open3.capture2(cmd)

  if status.success?
    begin
      json_data = JSON.parse(stdout)
      # Extract only cask tokens
      json_data['casks'].map { |c| c['name'] }
    rescue JSON::ParserError => e
      STDERR.puts "Error parsing JSON output from brew: #{e.message}"
      []
    end
  else
    STDERR.puts "Error running brew outdated command."
    []
  end
end

def get_running_apps
  # Get the list of running GUI apps and their bundle IDs using lsappinfo
  stdout, status = Open3.capture2("/usr/bin/lsappinfo list | /usr/bin/awk -F'\"' '/bundleID/{print $2}' | /usr/bin/sort -u")

  if status.success?
    stdout.split("\n").compact
  else
    STDERR.puts "Error getting running apps."
    []
  end
end

def quit_app(bundle_id, config_entry)
  if config_entry['unsafe_quit']
    puts config_entry['quit_message'] || "Please save your work in the application before continuing."
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
            console.log("Successfully quit application with Bundle ID: " + "#{bundle_id}" + "\n")
        } else {
            $.NSFileHandle.fileHandleWithStandardError.writeData(
                $.NSString.alloc.initWithUTF8String("Application with Bundle ID: " + "#{bundle_id}" + " is not running.\n").dataUsingEncoding($.NSUTF8StringEncoding)
            );
        }
    } catch (error) {
        // Handle error
        $.NSFileHandle.fileHandleWithStandardError.writeData(
            $.NSString.alloc.initWithUTF8String("Error while processing Bundle ID: " + "#{bundle_id}" + ". " + error.toString() + "\n").dataUsingEncoding($.NSUTF8StringEncoding)
        );
    }
    // Avoid returning a value to suppress unwanted output
    // undefined;
    EOS

  # Print the final JXA script for debugging
  # STDERR.puts "JXA Script:"
  # STDERR.puts jxa_script

  # Execute the JXA script
  stdout, stderr, status = Open3.capture3("osascript -l JavaScript", stdin_data: jxa_script)

  if status.success?
    puts stdout unless stdout.strip.empty?
  else
    $stderr.puts stderr unless stderr.strip.empty?
  end
end

def handle_quit_result(bundle_id, output)
  if output.include?("Successfully quit application")
    puts "Successfully quit application: #{bundle_id}"
    true
  elsif output.include?("is not running")
    puts "Application #{bundle_id} was not running."
    false
  else
    $stderr.puts "Warning: Failed to quit application with Bundle ID #{bundle_id} - #{output}"
    false
  end
end

def open_app(bundle_id)
  success = system("/usr/bin/open", "-b", bundle_id)

  unless success
    STDERR.puts "Warning: Failed to open application with Bundle ID #{bundle_id}."
  end
end

def upgrade_packages
  # Upgrade all outdated packages at once with specified options
  success = system("brew", "upgrade", "--greedy-auto-updates", "--fetch-HEAD", "--display-times")

  unless success
    STDERR.puts "Warning: Failed to upgrade packages."
  end

  success # Return whether the upgrade was successful or not.
end

# Main logic
begin
  # Run validation tests
  test_valid_bundle_id
  test_valid_homebrew_token

  # Attempt to reorganize the configuration file for better readability
  reorganize_config_file(CONFIG_FILE)

  # Load and validate configuration
  config = load_and_validate_configuration(CONFIG_FILE)

  # Display nicely formatted information about outdated packages
  display_outdated_packages

  # Get outdated casks and running apps
  outdated_cask_tokens = get_outdated_casks_json # Get structured data for processing.
  running_apps = get_running_apps

  # Determine which casks need to be quit and reopened
  # casks_to_quit_and_reopen = config.keys.select { |token| outdated_cask_tokens.include?(token) } # prints if in config file even if no bundle id is running
  casks_to_quit_and_reopen = config.keys.select do |token|
    # Check if the cask is outdated and if any associated bundle IDs are running
    outdated_cask_tokens.include?(token) && config[token]['bundle_ids'].any? { |bundle_id| running_apps.include?(bundle_id) }
  end

  if casks_to_quit_and_reopen.any?
    puts "The following casks are scheduled for upgrade and will require quitting/reopening:\n  #{casks_to_quit_and_reopen.join("\n  ")}"

    # Quit all associated apps if they are running (only for GUI apps)
    casks_to_quit_and_reopen.each do |cask_token|
      data = config[cask_token]

      data['bundle_ids'].each do |bundle_id|
        if running_apps.include?(bundle_id)
          puts "Quitting #{bundle_id}..."
          quit_app(bundle_id, data)
          handle_quit_result(bundle_id, output)
        else
          STDERR.puts "#{bundle_id} is not running, skipping quit."
        end
      end
    end
  end

  # Upgrade all outdated packages regardless of whether they are in the config file or not.
  puts "Upgrading all outdated packages..."
  upgraded_successfully = upgrade_packages

  # Reopen applications after upgrade (if they were previously running)
  if casks_to_quit_and_reopen.any?
    casks_to_quit_and_reopen.each do |cask_token|
      data = config[cask_token]

      data['bundle_ids'].each do |bundle_id|
        if running_apps.include?(bundle_id)
          puts "Reopening #{bundle_id}..."
          open_app(bundle_id)
        else
          STDERR.puts "#{bundle_id} was not running, skipping reopen."
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

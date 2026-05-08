#!/usr/bin/env ruby

# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

require 'yaml'
require 'open3'
require 'json'

# CONFIG_FILE = '/path/to/your/config.yml'
CONFIG_FILE = 'rubytest-config.yml'

# Load the configuration file
begin
  config = YAML.load_file(CONFIG_FILE)
rescue Errno::ENOENT
  STDERR.puts "Error: Configuration file not found at #{CONFIG_FILE}."
  exit 1
rescue Psych::SyntaxError => e
  STDERR.puts "Error: Failed to parse YAML configuration file. #{e.message}"
  exit 1
end

def display_outdated_packages
  cmd = "brew outdated --greedy-auto-updates --fetch-HEAD --verbose"
  stdout, status = Open3.capture2(cmd)

  if status.success?
    puts "Outdated packages:"
    puts stdout
  else
    STDERR.puts "Error running brew outdated command for verbose output."
    []
  end
end

def get_outdated_casks_json
  cmd = "brew outdated --cask --greedy-auto-updates --fetch-HEAD --json=v2"
  stdout, status = Open3.capture2(cmd)

  if status.success?
    begin
      json_data = JSON.parse(stdout)
      json_data['casks'].map { |cask| cask['token'] }
    rescue JSON::ParserError => e
      STDERR.puts "Error parsing JSON output from brew: #{e.message}"
      []
    end
  else
    STDERR.puts "Error running brew outdated command for JSON output."
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

def quit_app(bundle_id)
  success = system("/usr/bin/osascript", "-e", "quit application id \"#{bundle_id}\"")

  # jxa_script = <<-JXA
  #   var app = Application('com.apple.systemevents');
  #   var targetApp = Application('#{bundle_id}');
  #   targetApp.quit();
  # JXA
  #
  # success = system("/usr/bin/osascript -l JavaScript -e '#{jxa_script}'")

  unless success
    STDERR.puts "Warning: Failed to quit application with bundle ID #{bundle_id}."
  end
end

def open_app(bundle_id)
  success = system("/usr/bin/open", "-b", bundle_id)

  unless success
    STDERR.puts "Warning: Failed to open application with bundle ID #{bundle_id}."
  end
end

def upgrade_casks(cask_tokens)
  return if cask_tokens.empty?

  # Upgrade all outdated casks at once
  success = system("brew", "upgrade", "--cask", *cask_tokens)

  unless success
    STDERR.puts "Warning: Failed to upgrade casks: #{cask_tokens.join(', ')}."
  end
end

# Main logic
display_outdated_packages # Display nicely formatted output to the user.
outdated_casks = get_outdated_casks_json # Get structured data for processing.
running_apps = get_running_apps

# Find which outdated casks are in the config file
casks_to_upgrade = config.keys.select { |token| outdated_casks.include?(token) }

if casks_to_upgrade.any?
  puts "The following casks are outdated and will be upgraded: #{casks_to_upgrade.join(', ')}"

  # Quit all associated apps if they are running
  casks_to_upgrade.each do |cask_token|
    data = config[cask_token]

    data['bundle_ids'].each do |bundle_id|
      if running_apps.include?(bundle_id)
        puts "Quitting #{bundle_id}..."
        quit_app(bundle_id)
      else
        puts "#{bundle_id} is not running, skipping quit."
      end
    end
  end

  # Upgrade the casks
  puts "Upgrading casks..."
  upgrade_casks(casks_to_upgrade)

  # Reopen all associated apps after upgrade
  casks_to_upgrade.each do |cask_token|
    data = config[cask_token]

    data['bundle_ids'].each do |bundle_id|
      if running_apps.include?(bundle_id)
        puts "Reopening #{bundle_id}..."
        open_app(bundle_id)
      else
        puts "#{bundle_id} was not running, skipping reopen."
      end
    end
  end

else
  puts "No outdated casks found in the configuration file."
end

puts "Upgrade process complete."


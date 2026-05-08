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
  stdout, status = Open3.capture2("lsappinfo list | awk -F'\"' '/bundleID/{print $2}' | sort -u")

  if status.success?
    stdout.split("\n").compact
  else
    STDERR.puts "Error getting running apps."
    []
  end
end

def quit_app(bundle_id)
  jxa_script = <<-JXA
    var app = Application('com.apple.systemevents');
    var targetApp = Application('#{bundle_id}');
    targetApp.quit();
  JXA

  success = system("osascript -l JavaScript -e '#{jxa_script}'")
  
  unless success
    STDERR.puts "Warning: Failed to quit application with bundle ID #{bundle_id}."
  end
end

def open_app(bundle_id)
  success = system("open", "-b", bundle_id)
  
  unless success
    STDERR.puts "Warning: Failed to open application with bundle ID #{bundle_id}."
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
display_outdated_packages # Display nicely formatted output to the user.
outdated_cask_tokens = get_outdated_casks_json # Get structured data for processing.
running_apps = get_running_apps

# Find which outdated casks are in the config file (only casks)
casks_to_quit_and_reopen = config.keys.select { |token| outdated_cask_tokens.include?(token) }

if casks_to_quit_and_reopen.any?
  puts "The following casks are scheduled for upgrade and will require quitting/reopening: #{casks_to_quit_and_reopen.join(', ')}"

  # Quit all associated apps if they are running (only for GUI apps)
  casks_to_quit_and_reopen.each do |cask_token|
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
        puts "#{bundle_id} was not running, skipping reopen."
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


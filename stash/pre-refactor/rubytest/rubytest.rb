#!/usr/bin/env ruby

# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

require 'yaml'
require 'open3'
require 'json'

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

def get_outdated_casks
  cmd = "brew info --cask --json=v2 --installed"
  stdout, status = Open3.capture2(cmd)

  if status.success?
    begin
      json_data = JSON.parse(stdout)
      json_data['casks'].select { |cask| cask['outdated'] }.map { |cask| cask['token'] }
    rescue JSON::ParserError => e
      STDERR.puts "Error parsing JSON output from brew: #{e.message}"
      []
    end
  else
    STDERR.puts "Error running brew info command"
    []
  end
end

def get_running_apps
  # Get the list of running GUI apps and their bundle IDs using lsappinfo
  stdout, status = Open3.capture2("/usr/bin/lsappinfo list | /usr/bin/awk -F'\"' '/bundleID/{print $2}' | /usr/bin/sort -u")

  if status.success?
    stdout.split("\n").compact
  else
    STDERR.puts "Error getting running apps"
    []
  end
end

def quit_app(bundle_id)
  success = system("/usr/bin/osascript", "-e", "tell application id \"#{bundle_id}\" to quit")

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

def upgrade_cask(cask_token)
  success = system("brew", "upgrade", "--cask", cask_token)

  unless success
    STDERR.puts "Warning: Failed to upgrade cask #{cask_token}."
  end
end

# Main logic
outdated_casks = get_outdated_casks
running_apps = get_running_apps

config.each do |cask_token, data|
  if outdated_casks.include?(cask_token)
    puts "#{cask_token} is outdated. Upgrading..."

    # Quit all associated apps if they are running
    data['bundle_ids'].each do |bundle_id|
      if running_apps.include?(bundle_id)
        puts "Quitting #{bundle_id}..."
        quit_app(bundle_id)
      else
        puts "#{bundle_id} is not running, skipping quit."
      end
    end

    # Upgrade the cask
    puts "Upgrading #{cask_token}..."
    upgrade_cask(cask_token)

    # Reopen all associated apps if they were previously running
    data['bundle_ids'].each do |bundle_id|
      if running_apps.include?(bundle_id)
        puts "Reopening #{bundle_id}..."
        open_app(bundle_id)
      else
        puts "#{bundle_id} was not running, skipping reopen."
      end
    end

    puts "#{cask_token} upgrade complete."
  else
    puts "#{cask_token} is up to date."
  end
end

# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: strict
# frozen_string_literal: true

# https://chatgpt.com/c/677f5512-5718-800c-b8c6-5f12c300a5cd

# AppManager is responsible for managing the lifecycle of applications during
# an upgrade process. It handles checking if apps are running, quitting them
# safely (considering any marked as unsafe to quit), and reopening them after
# the upgrade is completed.
#
# The actual upgrade logic for Homebrew packages and macOS App Store applications
# is handled by separate components (`brew-upgrade.rb` and `mas-upgrade.rb`).
#
# AppManager interacts with configuration data loaded and validated by `ConfigManager`.
# It ensures that applications are properly managed according to the configuration
# settings, which include bundle IDs and flags indicating whether an app is unsafe
# to quit.
#
# Responsibilities:
# - Check if apps are running based on bundle IDs.
# - Handle quitting and reopening of apps with attention to unsafe quit warnings.
# - Cooperate with other components for executing the actual upgrade processes.
#
class AppManager
  def initialize(config)
    @config = config
  end

  def running?(bundle_id)
    # Logic to check if the app with the given bundle_id is running (e.g., using lsappinfo)
    # Returns true if the app is running, false otherwise
  end

  def quit_app(bundle_id)
    # Logic to quit the app (e.g., using AppleScript or other methods)
    # You would typically issue a command to quit the app with the given bundle_id
  end

  def prompt_for_unsafe_quit(app_name)
    # Display a warning message to the user about quitting the app unsafely
    # Using string formatting for multiline output
    warning_message = "Warning: The app #{app_name} is marked as unsafe to quit without saving."
    warning_message += " Do you want to continue? (y/n)"
    $stderr.puts warning_message
    response = gets.chomp
    response.downcase == "y"
  end

  def check_and_quit_app_if_needed(bundle_ids, app_name)
    bundle_ids.each do |bundle_id|
      next unless running?(bundle_id)

      app_config = @config.dig("apps", "homebrew").find { |app| app["bundle_ids"].include?(bundle_id) }
      unsafe_quit = app_config && app_config["unsafe_quit"]

      if unsafe_quit
        # Prompt the user if unsafe_quit is true
        if prompt_for_unsafe_quit(app_name)
          quit_app(bundle_id)
        else
          $stderr.puts "Skipping quit for #{app_name}."
        end
      else
        quit_app(bundle_id)
      end
    end
  end
end

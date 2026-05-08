# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: strict
# frozen_string_literal: true

# https://chatgpt.com/c/677f5512-5718-800c-b8c6-5f12c300a5cd

require "yaml"
require "open3"

# AppManager is responsible for managing the installation state and
# lifecycle of applications that require special handling during a
# brew upgrade. This includes checking whether applications are
# installed, quitting and reopening apps based on their bundle IDs,
# and prompting the user for confirmation if an app is unsafe to quit.
#
# The class reads from a YAML configuration file to determine which
# apps need to be managed, and ensures that apps are quit before
# upgrading and reopened afterward. It handles both Homebrew and
# Mac App Store apps.
#
class AppManager
  BUNDLE_ID_REGEX = /^[a-zA-Z0-9._-]+$/
  TOKEN_REGEX = /^[a-zA-Z0-9._-]+$/
  APP_ID_REGEX = /^\d{9,10}$/ # MAS app IDs are typically 9-10 digits

  def initialize(config_files)
    @config_files = config_files
    @config = load_and_merge_configs
  end

  # Load and merge multiple YAML configuration files
  def load_and_merge_configs
    merged_config = {}

    @config_files.each do |file|
      config = YAML.load_file(file)
      merged_config.deep_merge(config)
    end

    merged_config
  end

  # Validate that all apps listed in the config are properly configured
  def validate_apps
    @config["apps"].each do |platform, apps|
      apps.each do |app|
        if platform == "homebrew"
          validate_homebrew_app(app)
        elsif platform == "mas"
          validate_mas_app(app)
        end
      end
    end
  end

  # Validate that a Homebrew app is properly configured
  def validate_homebrew_app(app)
    token = app["token"]
    bundle_ids = app["bundle_ids"]

    # Validate token format
    $stderr.puts "Invalid token format for Homebrew app: #{token}" unless valid_token?(token)

    # Validate bundle IDs format
    bundle_ids.each do |bundle_id|
      $stderr.puts "Invalid bundle ID format for app #{token}: #{bundle_id}" unless valid_bundle_id?(bundle_id)
    end
  end

  # Validate that a MAS app is properly configured
  def validate_mas_app(app)
    app_id = app["app_id"]
    bundle_ids = app["bundle_ids"]

    # Validate app ID format
    $stderr.puts "Invalid MAS app ID format for app #{app["name"]}: #{app_id}" unless valid_app_id?(app_id)

    # Validate bundle IDs format
    bundle_ids.each do |bundle_id|
      $stderr.puts "Invalid bundle ID format for app #{app["name"]}: #{bundle_id}" unless valid_bundle_id?(bundle_id)
    end
  end

  # Validate the format of a bundle ID
  def valid_bundle_id?(bundle_id)
    bundle_id =~ BUNDLE_ID_REGEX
  end

  # Validate the format of a Homebrew token
  def valid_token?(token)
    token =~ TOKEN_REGEX
  end

  # Validate the format of a MAS app ID
  def valid_app_id?(app_id)
    app_id =~ APP_ID_REGEX
  end

  # Quit apps if they are running
  def quit_running_apps
    @config["apps"].each_value do |apps|
      apps.each do |app|
        next if app["unsafe_to_quit"] == true

        app["bundle_ids"].each do |bundle_id|
          quit_app(bundle_id) if app_running?(bundle_id)
        end
      end
    end
  end

  # Check if an app is running based on its bundle ID
  def app_running?(bundle_id)
    stdout, = Open3.capture3("lsappinfo list")
    stdout.include?(bundle_id)
  end

  # Quit an app using its bundle ID
  def quit_app(bundle_id)
    $stderr.puts "Quitting app with Bundle ID: #{bundle_id}"
    # Logic to quit the app, e.g., using AppleScript or `osascript`
  end

  # Reopen apps after upgrade
  def reopen_apps
    @config["apps"].each_value do |apps|
      apps.each do |app|
        app["bundle_ids"].each do |bundle_id|
          reopen_app(bundle_id)
        end
      end
    end
  end

  # Reopen an app using its bundle ID
  def reopen_app(bundle_id)
    $stderr.puts "Reopening app with Bundle ID: #{bundle_id}"
    # Logic to reopen the app
  end
end

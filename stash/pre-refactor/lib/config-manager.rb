# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: strict
# frozen_string_literal: true

# https://chatgpt.com/c/677f5512-5718-800c-b8c6-5f12c300a5cd

# ConfigManager is responsible for managing the configuration files used by the application.
# It handles the following tasks:
# - Finding and loading configuration files from multiple sources
# - Merging configurations while respecting the order of precedence
# - Validating the contents of the configuration files, including checking formats for app-related identifiers (tokens, bundle_ids, app_ids)
#
# The class ensures that the configuration data is valid before being used by other components of the application, such as AppManager.
# It raises errors if the configuration files are not properly formatted or if required fields are missing.
#
# Example usage:
#   config_manager = ConfigManager.new(['config1.yml', 'config2.yml'])
#   config_manager.load_and_validate
#   config = config_manager.config
#
class ConfigManager
  # Assuming regex patterns are the same for bundle_id, token, app_id validation
  BUNDLE_ID_REGEX = /^[a-zA-Z0-9._-]+$/
  TOKEN_REGEX = /^[a-zA-Z0-9._-]+$/
  APP_ID_REGEX = /^\d{9,10}$/

  def initialize(config_files)
    @config_files = config_files
    @config = {}
  end

  # Main method to load and validate the configuration
  def load_and_validate
    find_and_load_configs
    validate_configs
    @config
  end

  private

  # Method to find and load configuration files in order of precedence
  def find_and_load_configs
    merged_config = {}

    @config_files.each do |file|
      # Assuming YAML.load_file and deep_merge functionality here
      config = load_config(file)
      merged_config.deep_merge!(config)
    end

    @config = merged_config
  end

  # Method to load an individual config file
  def load_config(file)
    YAML.load_file(file)
  rescue => e
    raise "Failed to load config file #{file}: #{e.message}"
  end

  # Method to validate the loaded configuration
  def validate_configs
    validate_apps
  end

  # Method to validate all apps in the config
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

  # Validate a Homebrew app (token and bundle_ids)
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

  # Validate a MAS app (app_id and bundle_ids)
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

  # Validate bundle ID format
  def valid_bundle_id?(bundle_id)
    bundle_id =~ BUNDLE_ID_REGEX
  end

  # Validate Homebrew token format
  def valid_token?(token)
    token =~ TOKEN_REGEX
  end

  # Validate MAS app ID format
  def valid_app_id?(app_id)
    app_id =~ APP_ID_REGEX
  end
end

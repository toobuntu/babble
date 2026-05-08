# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: strict
# frozen_string_literal: true

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
  def initialize(config_file)
    # Load and parse the YAML config file
    @config = load_config(config_file)
  end

  # Load and parse the YAML config file
  def load_config(file)
    raise "Config file not found: #{file}" unless File.exist?(file)

    YAML.load_file(file)
  end

  # Main method to check and handle app installations
  def check_and_handle_apps
    check_homebrew_apps
    check_mas_apps
  end

  # Check and handle Homebrew apps
  def check_homebrew_apps
    @config["apps"]["homebrew"].each do |app|
      token = app["token"]
      bundle_ids = app["bundle_ids"]
      unsafe_to_quit = app["unsafe_to_quit"]

      installed = app_installed?(token, :brew)
      log_app_status("brew", token, installed)

      handle_unsafe_app(token, unsafe_to_quit, bundle_ids) if installed
    end
  end

  # Check and handle MAS apps
  def check_mas_apps
    @config["apps"]["mas"].each do |app|
      app_id = app["app_id"]
      bundle_ids = app["bundle_ids"]
      unsafe_to_quit = app["unsafe_to_quit"]

      installed = app_installed?(app_id, :mas)
      log_app_status("mas", app_id, installed)

      handle_unsafe_app(app_id, unsafe_to_quit, bundle_ids) if installed
    end
  end

  # Check if an app is installed via brew or mas
  def app_installed?(identifier, app_type)
    case app_type
    when :brew
      check_brew_installation(identifier)
    when :mas
      check_mas_installation(identifier)
    else
      raise "Unknown app type: #{app_type}"
    end
  end

  # Check if an app is installed via Homebrew
  def check_brew_installation(token)
    stdout, _, status = Open3.capture3("brew list")
    raise "brew list failed" unless status.success?

    stdout.include?(token)
  end

  # Check if an app is installed via MAS
  def check_mas_installation(app_id)
    stdout, _, status = Open3.capture3("mas list")
    raise "mas list failed" unless status.success?

    stdout.include?(app_id.to_s)
  end

  # Log the status of the app installation
  def log_app_status(app_type, identifier, installed)
    if installed
      $stderr.puts "[#{app_type}] #{identifier} is installed."
    else
      $stderr.puts "[#{app_type}] #{identifier} is not installed."
    end
  end

  # Handle unsafe app based on unsafe_to_quit
  def handle_unsafe_app(identifier, unsafe_to_quit, bundle_ids)
    if unsafe_to_quit
      $stderr.puts "Warning: #{identifier} is marked unsafe to quit without saving!"
      prompt_for_user_input
    end
    quit_and_reopen_apps(bundle_ids)
  end

  # Prompt the user for confirmation before proceeding
  def prompt_for_user_input
    $stderr.puts "Press Enter to continue or Ctrl+C to cancel..."
    gets
  end

  # Quit and reopen apps based on their bundle ids
  def quit_and_reopen_apps(bundle_ids)
    $stderr.puts "Quitting and reopening apps: #{bundle_ids.join(", ")}"

    # Quit apps
    bundle_ids.each { |bundle_id| quit_app(bundle_id) }

    # Perform upgrade (simulated by sleep or actual upgrade logic)
    $stderr.puts "Upgrading apps..."
    sleep(2) # Simulate upgrade

    # Reopen apps
    bundle_ids.each { |bundle_id| reopen_app(bundle_id) }
  end

  # Quit an app based on its bundle id
  def quit_app(bundle_id)
    $stderr.puts "Quitting app with bundle ID: #{bundle_id}"
    # Execute the quit command (use `osascript` or any relevant command to quit the app)
    system("osascript -e 'quit app \"#{bundle_id}\"'")
  end

  # Reopen an app based on its bundle id
  def reopen_app(bundle_id)
    $stderr.puts "Reopening app with bundle ID: #{bundle_id}"
    # Execute the reopen command (use `osascript` to open the app)
    system("open -b '#{bundle_id}'")
  end
end

# Usage Example:
config_file = "whimsical-quit-reopen.yml" # Path to the config file
app_manager = AppManager.new(config_file)
app_manager.check_and_handle_apps

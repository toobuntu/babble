# typed: strict
# frozen_string_literal: true

# macos_interface/display_alert.rb

require "rbconfig"
require_relative "dark_mode"

# The MacOSInterface module provides macOS-related utility classes for
# interacting with macOS-specific settings and features.
module MacOSInterface
  # Manages user alert dialogs and dynamically adjusts to macOS appearance settings.
  class DisplayAlert
    ICON_DIR = "../../../../../assets"
    ICONS = {
      light: "#{ICON_DIR}/refresh-dot-dark.svg".freeze,
      dark:  "#{ICON_DIR}/refresh-dot-light.svg".freeze,
    }.freeze

    # Public: Orchestrates the quit alert dialog
    def self.quit_alert(app_name)
      validate_app_name(app_name)
      display_alert(app_name)
    end

    # Validates the existence of icon files (Private)
    def self.validate_icon_files
      return if File.exist?(ICONS[:light]) && File.exist?(ICONS[:dark])

      raise "Icon files are missing. Ensure both '#{ICONS[:light]}' and '#{ICONS[:dark]}' exist."
    end

    # Validates the app name to ensure it's not nil or empty (Private)
    def self.validate_app_name(app_name)
      raise ArgumentError, "App name cannot be nil or empty." if app_name.nil? || app_name.strip.empty?
    end

    # Determines the appropriate icon path based on the system's appearance (Private)
    def self.icon_path
      MacOSInterface::DarkMode.enabled? ? ICONS[:dark] : ICONS[:light]
    end

    # Executes the quit alert command and returns a boolean based on user choice (Private)
    def self.display_alert(app_name)
      validate_icon_files
      icon = icon_path
      architecture = RbConfig::CONFIG["host_cpu"]
      command = "../../../swift/build/dist/quit_alert_#{architecture} --app-name '#{app_name}' --icon '#{icon}'"

      system(command) ? true : false
    end
  end
end

# Allow the script to run when executed
if __FILE__ == $PROGRAM_NAME
  begin
    # Ensure that an app name is provided
    app_name = ARGV[0]
    raise ArgumentError, "Usage: #{$PROGRAM_NAME} <app_name>" if app_name.nil? || app_name.strip.empty?

    # Call the listing method to start the test
    # Execute the quit alert
    puts
    puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
    if MacOSInterface::DisplayAlert.quit_alert(app_name)
      puts "User chose to continue. Proceeding with the update..."
      exit 0
    else
      puts "User canceled. Exiting..."
      exit 1
    end
  rescue ArgumentError => e
    warn e.message
    exit 1
  rescue => e
    warn "An unexpected error occurred: #{e.message}"
    exit 1
  end
  puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
end

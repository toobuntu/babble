# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: strict
# frozen_string_literal: true

require "open3"

# Module to handle macOS updates.
# Provides methods to list available updates and install them.
module MacOSUpdates
  def self.list_updates
    puts "\nListing all available updates to macOS..."
    puts "Would run `softwareupdate --list`"

    _, stderr, status = Open3.capture3(
      "/usr/sbin/softwareupdate",
      "--list",
    )

    unless status.success?
      puts "\nErrors occurred while checking for updates:"
      puts stderr unless stderr.empty?
      return
    end

    if stderr.include?("No new software available.")
      puts "No updates available."
      return
    end

    # Display available updates
    puts stderr unless stderr.empty?

    waiter("Press the Space bar to continue, or Ctrl-C to exit.")
    install_updates
  end

  def self.install_updates
    puts "\nInstalling all available updates to macOS..."
    puts "A system restart may occur if required to complete installation."
    puts "Would run `sudo softwareupdate --install --all --restart`"

    status = system(
      "/usr/bin/sudo",
      "/usr/sbin/softwareupdate",
      "--install",
      "--all",
      "--restart",
    )

    if status
      puts "\nUpdates installed successfully."
    else
      puts "\nAn error occurred during the update installation."
    end
  end
end

# Allow the script to run when executed
if __FILE__ == $PROGRAM_NAME
  # require_relative "macos_updates"

  puts
  puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
  # Call the listing method to start the test
  MacOSUpdates.list_updates
  puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
end

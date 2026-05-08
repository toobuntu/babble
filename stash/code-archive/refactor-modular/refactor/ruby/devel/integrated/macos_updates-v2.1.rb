# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: strict
# frozen_string_literal: true

require "open3"
require_relative "waiter"

# Module to handle macOS updates.
# Provides methods to list available updates and install them.
module MacOSUpdates
  def self.list_updates
    puts "\nListing all available updates to macOS. This may take some time."
    puts "Would run `softwareupdate --list`"
    Waiter.waiter("run_command")
    puts "Please wait..."

    stdout, stderr, status = Open3.capture3(
    # _, stderr, status = Open3.capture3(
      "/usr/sbin/softwareupdate",
      "--list",
    )

    unless status.success?
      $stderr.puts "\nErrors occurred while checking for updates:"
      $stderr.puts stderr unless stderr.empty?
      return
    end

    if stderr.include?("No new software available.")
      puts "No updates available."
      # $stderr.puts stderr
      return
    end

    # Display available updates
    puts stdout unless stdout.empty?
    $stderr.puts stderr unless stderr.empty?

    install_updates
  end

  def self.install_updates
    puts "\nInstalling all available updates to macOS..."
    puts "A system restart may occur if required to complete installation."
    puts "Would run `sudo softwareupdate --install --all --restart`"
    Waiter.waiter("run_command")

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
      $stderr.puts "\nAn error occurred during the update installation."
    end
  end
end

# Allow the script to run when executed
if __FILE__ == $PROGRAM_NAME

  puts
  puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
  # Call the listing method to start the test
  MacOSUpdates.list_updates
  puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
end

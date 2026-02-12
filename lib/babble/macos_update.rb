# typed: strict
# frozen_string_literal: true

require "open3"
require_relative "waiter"

module Babble
  class MacOSUpdate
    class << self
      def run
        unless updates_available?
          puts "No macOS system updates available."
          return
        end

        display_available_updates

        puts "\nPreparing to install macOS updates..."
        Waiter.waiter("run_command", continuation_message: "Installing macOS updates...")

        install_updates

        puts "\n✓ macOS update complete."
      end

      private

      def updates_available?
        stdout, _, status = Open3.capture3("softwareupdate", "--list")
        return false unless status.success?

        !stdout.include?("No new software available.")
      end

      def display_available_updates
        puts "\nAvailable macOS updates:"
        stdout, _, status = Open3.capture3("softwareupdate", "--list")

        if status.success?
          puts stdout
        else
          $stderr.puts "Failed to list updates"
        end
      end

      def install_updates
        success = system("sudo", "softwareupdate", "--install", "--all", "--restart")

        unless success
          $stderr.puts "Warning: softwareupdate failed"
        end

        success
      end
    end
  end
end

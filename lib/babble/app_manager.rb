# typed: strict
# frozen_string_literal: true

require "open3"
require "json"
require "fileutils"
require_relative "bundle_launcher"

module Babble
  class AppManager
    SWIFT_CACHE_DIR = File.expand_path("~/.cache/babble")
    QUIT_ALERT_BINARY = File.join(SWIFT_CACHE_DIR, "quit_alert")

    class << self
      def running_bundle_ids
        stdout, stderr, status = Open3.capture3("lsappinfo", "list")

        unless status.success?
          $stderr.puts "Failed to get running apps: #{stderr}"
          return []
        end

        bundle_ids = []
        stdout.each_line do |line|
          if line =~ /"CFBundleIdentifier"="([^"]+)"/
            bundle_ids << Regexp.last_match(1)
          end
        end

        bundle_ids.uniq
      end

      def quit_app(bundle_id)
        jxa_script = <<~JAVASCRIPT
          const app = Application(#{bundle_id.to_json});
          if (app.running()) {
            app.quit();
          }
        JAVASCRIPT

        stdout, stderr, status = Open3.capture3(
          "osascript", "-l", "JavaScript", "-e", jxa_script
        )

        unless status.success?
          $stderr.puts "Failed to quit #{bundle_id}: #{stderr}"
          return false
        end

        true
      end

      def quit_with_confirmation(bundle_id, app_name)
        ensure_quit_alert_compiled

        status = system(QUIT_ALERT_BINARY, app_name)
        exit_code = $?.exitstatus

        case exit_code
        when 0
          quit_app(bundle_id)
          true
        when 1
          $stderr.puts "User cancelled quit for #{app_name}"
          false
        when 2
          $stderr.puts "Failed to load icon for quit alert"
          false
        when 3
          $stderr.puts "Invalid arguments for quit alert"
          false
        else
          $stderr.puts "Unknown error from quit alert: #{exit_code}"
          false
        end
      end

      def reopen_app(bundle_id, timeout: 10)
        BundleLauncher.launch(bundle_id, timeout: timeout)
      rescue StandardError => e
        $stderr.puts "Failed to reopen #{bundle_id}: #{e.message}"
        false
      end

      private

      def ensure_quit_alert_compiled
        return if File.exist?(QUIT_ALERT_BINARY)

        FileUtils.mkdir_p(SWIFT_CACHE_DIR)

        swift_source = File.expand_path("../../swift/src/quit_alert.swift", __dir__)
        unless File.exist?(swift_source)
          raise "Swift source not found: #{swift_source}"
        end

        $stderr.puts "Compiling Swift quit alert..."

        arch = `uname -m`.strip
        target = case arch
                 when "arm64"
                   "arm64-apple-macos13"
                 when "x86_64"
                   "x86_64-apple-macos13"
                 else
                   raise "Unsupported architecture: #{arch}"
                 end

        stdout, stderr, status = Open3.capture3(
          "xcrun", "swiftc",
          "-target", target,
          "-o", QUIT_ALERT_BINARY,
          swift_source
        )

        unless status.success?
          raise "Failed to compile Swift quit alert: #{stderr}"
        end

        $stderr.puts "Swift quit alert compiled successfully."
      end
    end
  end
end

# typed: strict
# frozen_string_literal: true

require "open3"
require_relative "config_manager"
require_relative "app_manager"
require_relative "waiter"

module Babble
  class MasUpgrade
    class << self
      def run(config_file)
        unless mas_installed?
          puts "\nmas (Mac App Store CLI) is not installed. Skipping MAS upgrades."
          puts "Install with: brew install mas"
          return
        end

        config = ConfigManager.load_and_validate_configuration(config_file)
        mas_entries = config.dig("apps", "mas") || []

        unless display_outdated_apps
          puts "No Mac App Store upgrades needed."
          return
        end

        outdated_ids = outdated_app_ids
        running_apps = AppManager.running_bundle_ids

        apps_to_manage = mas_entries.select do |entry|
          outdated_ids.include?(entry["app_id"]) &&
            entry["bundle_ids"].is_a?(Array) &&
            entry["bundle_ids"].any? { |bundle_id| running_apps.include?(bundle_id) }
        end

        if apps_to_manage.any?
          puts "\nThe following apps will be quit for upgrade:"
          apps_to_manage.each { |entry| puts "  - #{entry["name"]}" }
          puts

          quit_apps(apps_to_manage, running_apps)
        end

        puts "\nPreparing to upgrade Mac App Store apps..."
        Waiter.waiter("run_command", continuation_message: "Upgrading Mac App Store apps...")

        upgrade_apps

        if apps_to_manage.any?
          reopen_apps(apps_to_manage, running_apps)
        end

        puts "\n✓ Mac App Store upgrade complete."
      end

      private

      def mas_installed?
        system("command -v mas > /dev/null 2>&1")
      end

      def display_outdated_apps
        stdout, _, status = Open3.capture3("mas", "outdated")
        return false unless status.success?

        lines = stdout.strip.split("\n")
        return false if lines.empty?

        puts "\nOutdated Mac App Store apps:"
        lines.each { |line| puts "  #{line}" }

        true
      end

      def outdated_app_ids
        stdout, _, status = Open3.capture3("mas", "outdated")
        return [] unless status.success?

        stdout.split("\n").map do |line|
          line.split.first.to_i
        end
      end

      def quit_apps(apps_to_manage, running_apps)
        apps_to_manage.each do |entry|
          entry["bundle_ids"].each do |bundle_id|
            next unless running_apps.include?(bundle_id)

            app_name = entry["name"]

            if entry["unsafe_to_quit"]
              success = AppManager.quit_with_confirmation(bundle_id, app_name)
              exit(1) unless success
            else
              puts "Quitting #{app_name}..."
              AppManager.quit_app(bundle_id)
            end

            sleep 0.5
          end
        end
      end

      def upgrade_apps
        success = system("mas", "upgrade")

        unless success
          $stderr.puts "Warning: mas upgrade failed"
        end

        success
      end

      def reopen_apps(apps_to_manage, running_apps)
        puts "\nReopening applications..."

        apps_to_manage.each do |entry|
          entry["bundle_ids"].each do |bundle_id|
            next unless running_apps.include?(bundle_id)

            app_name = entry["name"]
            puts "Reopening #{app_name}..."

            AppManager.reopen_app(bundle_id, timeout: 10)
            sleep 0.5
          end
        end
      end
    end
  end
end

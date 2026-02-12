# typed: strict
# frozen_string_literal: true

require "json"
require "open3"
require "fileutils"
require_relative "constants"
require_relative "config_manager"
require_relative "app_manager"
require_relative "quarantine_purger"
require_relative "waiter"

module Babble
  class BrewUpgrade
    class << self
      def run(config_file)
        config = ConfigManager.load_and_validate_configuration(config_file)
        homebrew_entries = config.dig("apps", "homebrew") || []

        update_if_needed

        unless display_outdated_packages
          puts "No Homebrew upgrades needed."
          return
        end

        outdated_tokens = outdated_casks_json
        running_apps = AppManager.running_bundle_ids

        apps_to_manage = homebrew_entries.select do |entry|
          outdated_tokens.include?(entry["token"]) &&
            entry["bundle_ids"].is_a?(Array) &&
            entry["bundle_ids"].any? { |bundle_id| running_apps.include?(bundle_id) }
        end

        if apps_to_manage.any?
          puts "\nThe following apps will be quit for upgrade:"
          apps_to_manage.each { |entry| puts "  - #{entry["token"]}" }
          puts

          quit_apps(apps_to_manage, running_apps)
        end

        puts "\nPreparing to upgrade all outdated packages..."
        Waiter.waiter("run_command", continuation_message: "Upgrading outdated packages...")

        upgrade_packages

        if apps_to_manage.any?
          reopen_apps(apps_to_manage, running_apps)
        end

        puts "\n✓ Homebrew upgrade complete."
      end

      private

      def update_if_needed
        last_update_file = File.join(CACHE_DIR, "last_brew_update")
        
        if !File.exist?(last_update_file) || (Time.now - File.mtime(last_update_file)) > 3600
          puts "Updating Homebrew..."
          system("brew", "update")
          
          FileUtils.mkdir_p(File.dirname(last_update_file))
          FileUtils.touch(last_update_file)
        end
      end

      def display_outdated_packages
        stdout, _, status = Open3.capture3("brew", "outdated", "--json=v2")
        return false unless status.success?

        data = JSON.parse(stdout)
        formulae = data["formulae"] || []
        casks = data["casks"] || []

        return false if formulae.empty? && casks.empty?

        unless formulae.empty?
          puts "\nOutdated formulae:"
          formulae.each do |formula|
            puts "  #{formula["name"]} (#{formula["installed_versions"].first} -> #{formula["current_version"]})"
          end
        end

        unless casks.empty?
          puts "\nOutdated casks:"
          casks.each do |cask|
            puts "  #{cask["token"]} (#{cask["installed_versions"].first} -> #{cask["current_version"]})"
          end
        end

        true
      end

      def outdated_casks_json
        stdout, _, status = Open3.capture3("brew", "outdated", "--cask", "--json=v2")
        return [] unless status.success?

        data = JSON.parse(stdout)
        casks = data["casks"] || []
        casks.map { |cask| cask["token"] }
      end

      def quit_apps(apps_to_manage, running_apps)
        apps_to_manage.each do |entry|
          entry["bundle_ids"].each do |bundle_id|
            next unless running_apps.include?(bundle_id)

            app_name = entry["token"].split("-").map(&:capitalize).join(" ")

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

      def upgrade_packages
        success = system(
          "brew", "upgrade",
          "--greedy-auto-updates",
          "--fetch-HEAD",
          "--display-times"
        )

        unless success
          $stderr.puts "Warning: brew upgrade failed"
        end

        success
      end

      def reopen_apps(apps_to_manage, running_apps)
        puts "\nReopening applications..."

        apps_to_manage.each do |entry|
          QuarantinePurger.run(entry["token"], debug: false)

          entry["bundle_ids"].each do |bundle_id|
            next unless running_apps.include?(bundle_id)

            app_name = entry["token"].split("-").map(&:capitalize).join(" ")
            puts "Reopening #{app_name}..."

            AppManager.reopen_app(bundle_id, timeout: 10)
            sleep 0.5
          end
        end
      end
    end
  end
end

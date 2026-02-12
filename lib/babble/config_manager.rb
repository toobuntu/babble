# typed: strict
# frozen_string_literal: true

require "yaml"
require "open3"

module Babble
  class ConfigManager
    class << self
      def yq_available?
        ENV["PATH"].split(File::PATH_SEPARATOR).any? do |directory|
          File.executable?(File.join(directory, "yq"))
        end
      end

      def valid_bundle_id?(bundle_id)
        bundle_id.match?(/^[[:alnum:].-]+$/i)
      end

      def valid_homebrew_token?(token)
        token.match?(/^[a-z0-9]+(-[a-z0-9]+)*(@[a-z0-9.-]+)?$/)
      end

      def validate_config(raw_config)
        valid_config = { "apps" => { "homebrew" => [], "mas" => [] } }
        conflicts = []
        validation_errors = []
        structural_issues = []

        homebrew_entries = raw_config.dig("apps", "homebrew")
        unless homebrew_entries.is_a?(Array)
          structural_issues << "'apps > homebrew' is missing or is not an array."
          homebrew_entries = []
        end

        homebrew_entries.each do |entry|
          token = entry["token"]
          bundle_ids = entry["bundle_ids"]

          unless valid_homebrew_token?(token)
            validation_errors << "Invalid Homebrew token: #{token}"
            next
          end

          valid_entry = {
            "token"          => token,
            "bundle_ids"     => [],
            "unsafe_to_quit" => false,
            "quit_message"   => nil,
          }

          if bundle_ids.is_a?(Array)
            valid_bundle_ids = bundle_ids.select { |id| valid_bundle_id?(id) }
            invalid_bundle_ids = bundle_ids - valid_bundle_ids
            validation_errors.concat(invalid_bundle_ids.map { |id| "Invalid Bundle ID for cask #{token}: #{id}" })
            valid_entry["bundle_ids"] = valid_bundle_ids
          else
            structural_issues << "Missing or invalid 'bundle_ids' for cask #{token}"
          end

          if entry.key?("unsafe_to_quit")
            existing_value = valid_entry["unsafe_to_quit"]
            new_value = entry["unsafe_to_quit"]
            if !existing_value.nil? && (existing_value != new_value)
              conflicts << "Conflicting 'unsafe_to_quit' values for cask #{token}"
            end
            valid_entry["unsafe_to_quit"] = new_value
          end

          if entry.key?("quit_message")
            existing_value = valid_entry["quit_message"]
            new_value = entry["quit_message"].to_s
            if existing_value && (existing_value != new_value)
              conflicts << "Conflicting 'quit_message' values for cask #{token}"
            end
            valid_entry["quit_message"] = new_value
          end

          valid_config["apps"]["homebrew"] << valid_entry
        end

        mas_entries = raw_config.dig("apps", "mas")
        unless mas_entries.is_a?(Array)
          structural_issues << "'apps > mas' is missing or is not an array."
          mas_entries = []
        end

        mas_entries.each do |entry|
          app_id = entry["app_id"]
          bundle_ids = entry["bundle_ids"]

          unless app_id.is_a?(Integer)
            validation_errors << "Invalid MAS app_id: #{app_id}"
            next
          end

          valid_mas_entry = {
            "app_id"         => app_id,
            "name"           => entry["name"],
            "bundle_ids"     => [],
            "unsafe_to_quit" => false,
            "quit_message"   => nil,
          }

          if bundle_ids.is_a?(Array)
            valid_bundle_ids = bundle_ids.select { |id| valid_bundle_id?(id) }
            invalid_bundle_ids = bundle_ids - valid_bundle_ids
            validation_errors.concat(invalid_bundle_ids.map do |id|
              "Invalid Bundle ID for MAS app #{app_id}: #{id} - #{entry["name"]}"
            end)
            valid_mas_entry["bundle_ids"] = valid_bundle_ids
          else
            structural_issues << "Missing or invalid 'bundle_ids' for MAS app #{app_id} - #{entry["name"]}"
          end

          if entry.key?("unsafe_to_quit")
            existing_value = valid_mas_entry["unsafe_to_quit"]
            new_value = entry["unsafe_to_quit"]
            if !existing_value.nil? && (existing_value != new_value)
              conflicts << "Conflicting 'unsafe_to_quit' values for MAS app #{app_id} - #{entry["name"]}"
            end
            valid_mas_entry["unsafe_to_quit"] = new_value
          end

          if entry.key?("quit_message")
            existing_value = valid_mas_entry["quit_message"]
            new_value = entry["quit_message"].to_s
            if existing_value && (existing_value != new_value)
              conflicts << "Conflicting 'quit_message' values for MAS app #{app_id} - #{entry["name"]}"
            end
            valid_mas_entry["quit_message"] = new_value
          end

          valid_config["apps"]["mas"] << valid_mas_entry
        end

        [valid_config, conflicts, validation_errors, structural_issues]
      end

      def load_and_validate_configuration(config_file)
        unless File.exist?(config_file)
          raise "Configuration file not found: #{config_file}"
        end

        raw_config = YAML.load_file(config_file)
        valid_config, conflicts, validation_errors, structural_issues = validate_config(raw_config)

        unless structural_issues.empty?
          $stderr.puts "Structural issues found in configuration:"
          structural_issues.each { |issue| $stderr.puts "  - #{issue}" }
        end

        unless validation_errors.empty?
          $stderr.puts "Validation errors found in configuration:"
          validation_errors.each { |error| $stderr.puts "  - #{error}" }
        end

        unless conflicts.empty?
          $stderr.puts "Conflicts found in configuration:"
          conflicts.each { |conflict| $stderr.puts "  - #{conflict}" }
        end

        if !structural_issues.empty? || !validation_errors.empty?
          raise "Configuration validation failed"
        end

        valid_config
      end

      def check_duplicates(config_file)
        return unless yq_available?

        stdout, stderr, status = Open3.capture3(
          "yq", "eval", ".apps.homebrew[].token", config_file
        )

        unless status.success?
          $stderr.puts "Failed to check for duplicate tokens: #{stderr}"
          return
        end

        tokens = stdout.split("\n")
        duplicates = tokens.select { |token| tokens.count(token) > 1 }.uniq

        unless duplicates.empty?
          $stderr.puts "Duplicate Homebrew tokens found:"
          duplicates.each { |token| $stderr.puts "  - #{token}" }
        end
      end

      def reorganize_config_file(config_file)
        unless yq_available?
          $stderr.puts "Note: yq is not installed. Skipping config reorganization."
          $stderr.puts "Install yq with: brew install yq"
          return
        end

        temp_file = "#{config_file}.tmp"

        stdout, stderr, status = Open3.capture3(
          "yq", "eval", ".apps.homebrew |= sort_by(.token) | .apps.mas |= sort_by(.app_id)",
          config_file
        )

        unless status.success?
          $stderr.puts "Failed to reorganize config file: #{stderr}"
          return
        end

        File.write(temp_file, stdout)
        File.rename(temp_file, config_file)
        $stderr.puts "Config file reorganized and sorted."
      end
    end
  end
end

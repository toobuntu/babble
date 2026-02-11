# lib/config/loader.rb
# frozen_string_literal: true
#
# This class loads configuration files from several predetermined locations,
# reorders each file using yq if available, and explicitly merges
# the configuration for apps.homebrew (keyed by "token") and apps.mas (keyed
# by "app_id"). Duplicate entries are merged with warnings, using conservative
# rules (e.g. for booleans).
#
# The final merged configuration is converted into the original schema
# (i.e. arrays of mappings) and cached in a temporary file.
#
require "yaml"
require "tmpdir"
require "fileutils"
require_relative "reorganizer"

module Config
  class Loader
    CONFIG_FILE_LOCATIONS = [
      "/etc/Bundlefile.yml",
      "#{Dir.home}/.config/babble/Bundlefile.yml",
      "#{Dir.home}/.Bundlefile.yml",
      "./.Bundlefile.yml",
      "./Bundlefile.yml"
    ].freeze

    TEMP_FILE = File.join(Dir.tmpdir, "merged_bundlefile.yml").freeze

    class << self
      def run
        CONFIG_FILE_LOCATIONS.each do |path|
          if File.exist?(path)
            Config::Reorganizer.reorder_file(path)
          end
        end

        if temp_file_fresh?
          $stderr.puts "Using cached merged config: #{TEMP_FILE}"
          return YAML.safe_load(File.read(TEMP_FILE))
        end

        merged = { "apps" => { "homebrew" => {}, "mas" => {} } }
        CONFIG_FILE_LOCATIONS.each do |path|
          next unless File.exist?(path)
          begin
            raw = YAML.safe_load_file(path) || {}
            merge_section!(merged, raw, "homebrew") do |entry|
              merge_homebrew_entry(entry)
            end
            merge_section!(merged, raw, "mas") do |entry|
              merge_mas_entry(entry)
            end
          rescue Psych::SyntaxError => e
            $stderr.puts "Warning: Failed to parse YAML at #{path}: #{e.message}"
          end
        end

        final_config = {
          "apps" => {
            "homebrew" => merged["apps"]["homebrew"].values,
            "mas"      => merged["apps"]["mas"].values
          }
        }

        if Reorganizer.yq_available?
          File.write(TEMP_FILE, YAML.dump(final_config))
          system("yq", "eval",
            '.apps.homebrew |= sort_by(.token) | ' \
            '.apps.mas |= sort_by(.name) | ' \
            '(.apps.homebrew[].bundle_ids) |= sort | ' \
            '(.apps.mas[].bundle_ids) |= sort', TEMP_FILE, "-i")
          final_config = YAML.safe_load(File.read(TEMP_FILE))
        end

        File.write(TEMP_FILE, YAML.dump(final_config))
        setup_temp_file_cleanup
        final_config
      end

      private

      def temp_file_fresh?
        return false unless File.exist?(TEMP_FILE)
        temp_mtime = File.mtime(TEMP_FILE)
        CONFIG_FILE_LOCATIONS.each do |path|
          if File.exist?(path) && File.mtime(path) > temp_mtime
            return false
          end
        end
        true
      end

      def setup_temp_file_cleanup
        at_exit { FileUtils.rm_f(TEMP_FILE) }
        Signal.trap("SIGINT") do
          FileUtils.rm_f(TEMP_FILE)
          exit
        end
        Signal.trap("SIGTERM") do
          FileUtils.rm_f(TEMP_FILE)
          exit
        end
      end

      def merge_section!(merged_config, raw_config, section)
        entries = raw_config.dig("apps", section)
        return unless entries.is_a?(Array)
        entries.each do |entry|
          key = (section == "homebrew") ? entry["token"] : entry["app_id"]
          next if key.nil?
          new_entry = yield(entry)
          next if new_entry.nil?
          if merged_config["apps"][section].key?(key)
            merged_config["apps"][section][key] =
              deep_merge_entries(
                merged_config["apps"][section][key],
                new_entry, section
              )
          else
            merged_config["apps"][section][key] = new_entry
          end
        end
      end

      def merge_homebrew_entry(entry)
        token = entry["token"]
        unless token.is_a?(String) &&
               token.match(/^[a-z0-9]+(-[a-z0-9]+)*(@[a-z0-9.-]+)?$/)
          $stderr.puts "Warning: Invalid Homebrew token: #{token.inspect}"
          return nil
        end
        {
          "token"             => token,
          "bundle_ids"        => valid_bundle_ids(entry["bundle_ids"]),
          "unsafe_to_quit"    => entry.key?("unsafe_to_quit") ? entry["unsafe_to_quit"] : false,
          "quit_message"      => entry["quit_message"].is_a?(String) ? entry["quit_message"] : nil,
          "bypass_gatekeeper" => entry.key?("bypass_gatekeeper") ? entry["bypass_gatekeeper"] : false
        }
      end

      def merge_mas_entry(entry)
        app_id = entry["app_id"]
        unless app_id.is_a?(Integer) && app_id.to_s.match(/^\d{9,10}$/)
          $stderr.puts "Warning: Invalid MAS app_id: #{app_id.inspect}"
          return nil
        end
        {
          "app_id"     => app_id,
          "name"       => entry["name"].is_a?(String) ? entry["name"] : nil,
          "bundle_ids" => valid_bundle_ids(entry["bundle_ids"]),
          "unsafe_to_quit" => entry.key?("unsafe_to_quit") ? entry["unsafe_to_quit"] : false,
          "quit_message"   => entry["quit_message"].is_a?(String) ? entry["quit_message"] : nil
        }
      end

      def valid_bundle_ids(bundle_ids)
        return [] unless bundle_ids.is_a?(Array)
        valid = bundle_ids.each_with_object([]) do |bid, arr|
          if bid.is_a?(String) && bid.match(/^[[:alnum:].-]+$/i)
            arr << bid
          else
            $stderr.puts "Warning: Invalid bundle id: #{bid.inspect}"
          end
        end
        valid.uniq
      end

      def deep_merge_entries(old_entry, new_entry, section)
        merged = old_entry.dup
        merged["bundle_ids"] = (old_entry["bundle_ids"] + new_entry["bundle_ids"]).uniq

        if section == "homebrew"
          if old_entry["unsafe_to_quit"] != new_entry["unsafe_to_quit"]
            $stderr.puts("Warning: Conflict for token #{old_entry['token']} on " \
                          "unsafe_to_quit - defaulting to true.")
          end
          merged["unsafe_to_quit"] = (old_entry["unsafe_to_quit"] ||
                                      new_entry["unsafe_to_quit"])
          if old_entry["bypass_gatekeeper"] != new_entry["bypass_gatekeeper"]
            $stderr.puts("Warning: Conflict for token #{old_entry['token']} on " \
                          "bypass_gatekeeper - defaulting to true if any true.")
          end
          merged["bypass_gatekeeper"] = (old_entry["bypass_gatekeeper"] ||
                                         new_entry["bypass_gatekeeper"])
          if old_entry["quit_message"] && new_entry["quit_message"] &&
             (old_entry["quit_message"] != new_entry["quit_message"])
            $stderr.puts("Warning: Conflict for token #{old_entry['token']} on " \
                          "quit_message - choosing higher priority value.")
          end
          merged["quit_message"] = new_entry["quit_message"] ||
                                   old_entry["quit_message"]
        elsif section == "mas"
          if old_entry["unsafe_to_quit"] != new_entry["unsafe_to_quit"]
            $stderr.puts("Warning: Conflict for MAS app_id #{old_entry['app_id']} on " \
                          "unsafe_to_quit - defaulting to true.")
          end
          merged["unsafe_to_quit"] = (old_entry["unsafe_to_quit"] ||
                                      new_entry["unsafe_to_quit"])
          if old_entry["quit_message"] && new_entry["quit_message"] &&
             (old_entry["quit_message"] != new_entry["quit_message"])
            $stderr.puts("Warning: Conflict for MAS app_id #{old_entry['app_id']} on " \
                          "quit_message - choosing higher priority value.")
          end
          merged["quit_message"] = new_entry["quit_message"] ||
                                   old_entry["quit_message"]
          if old_entry["name"] && new_entry["name"] &&
             (old_entry["name"] != new_entry["name"])
            $stderr.puts("Warning: Conflict for MAS app_id #{old_entry['app_id']} on " \
                          "name - choosing higher priority value.")
          end
          merged["name"] = new_entry["name"] || old_entry["name"]
        end
        merged
      end

      private :temp_file_fresh?, :setup_temp_file_cleanup, :merge_section!,
              :merge_homebrew_entry, :merge_mas_entry, :valid_bundle_ids,
              :deep_merge_entries
    end
  end
end

# copilot

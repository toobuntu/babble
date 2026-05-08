# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# lib/config/loader.rb
# typed: strict
# frozen_string_literal: true

require "yaml"
require "tmpdir"
require "fileutils"
require_relative "reorganizer"

module Config
  class Loader
    CONFIG_FILE_LOCATIONS = [
      "/etc/Bundlefile.yml",
      "#{Dir.home}/.config/bundle/Bundlefile.yml",  # assuming 'bundle' is the program name
      "#{Dir.home}/.Bundlefile.yml",
      "./.Bundlefile.yml",
      "./Bundlefile.yml"
    ].freeze

    # We use a well-known temp file to cache our merged config.
    TEMP_FILE = File.join(Dir.tmpdir, "merged_bundlefile.yml").freeze

    # Public entry point.
    def self.run
      # For each source file in our list, run reordering independently.
      CONFIG_FILE_LOCATIONS.each do |path|
        Reorganizer.reorder_file(path) if File.exist?(path)
      end

      # Check if a merged temp file exists and is fresh.
      if temp_file_fresh?
        $stderr.puts "Using cached merged config from TEMP_FILE."
        return YAML.safe_load(File.read(TEMP_FILE))
      end

      merged = { "apps" => { "homebrew" => {}, "mas" => {} } }

      # Process each config file in order of increasing priority.
      CONFIG_FILE_LOCATIONS.each do |path|
        next unless File.exist?(path)
        begin
          raw = YAML.safe_load_file(path) || {}
          merge_section!(merged, raw, "homebrew") { |entry| merge_homebrew_entry(entry) }
          merge_section!(merged, raw, "mas") { |entry| merge_mas_entry(entry) }
        rescue Psych::SyntaxError => e
          $stderr.puts "Warning: Failed to parse YAML at #{path}: #{e.message}"
        end
      end

      # Convert merged hashes (keyed by token/app_id) into arrays.
      final_config = {
        "apps" => {
          "homebrew" => merged["apps"]["homebrew"].values,
          "mas"      => merged["apps"]["mas"].values
        }
      }

      # Post-process the final merged config with yq if available.
      if Reorganizer.yq_available?
        File.write(TEMP_FILE, YAML.dump(final_config))
        # Run yq in-place on the temp file to enforce deduplication and ordering.
        system("yq", "eval", ".", TEMP_FILE, "-i")
        final_config = YAML.safe_load(File.read(TEMP_FILE))
      else
        # Fallback: Ruby’s uniq already used while merging arrays.
      end

      # Write the final config to the temp file.
      File.write(TEMP_FILE, YAML.dump(final_config))
      setup_temp_file_cleanup

      final_config
    end

    private

    # Set up at_exit and signal traps to clean up the TEMP_FILE.
    def self.setup_temp_file_cleanup
      at_exit { File.delete(TEMP_FILE) if File.exist?(TEMP_FILE) }
      Signal.trap("SIGINT")  { File.delete(TEMP_FILE) if File.exist?(TEMP_FILE); exit }
      Signal.trap("SIGTERM") { File.delete(TEMP_FILE) if File.exist?(TEMP_FILE); exit }
    end

    # Check that none of our source files have been updated after the temp file.
    def self.temp_file_fresh?
      return false unless File.exist?(TEMP_FILE)
      temp_mtime = File.mtime(TEMP_FILE)
      CONFIG_FILE_LOCATIONS.each do |path|
        return false if File.exist?(path) && File.mtime(path) > temp_mtime
      end
      true
    end

    # Yield each entry in the given section (e.g. "homebrew" or "mas") from raw_config.
    def self.merge_section!(merged_config, raw_config, section)
      entries = raw_config.dig("apps", section)
      return unless entries.is_a?(Array)
      entries.each do |entry|
        key = section == "homebrew" ? entry["token"] : entry["app_id"]
        next if key.nil?
        new_entry = yield(entry)
        next if new_entry.nil?  # Skip invalid entries.
        if merged_config["apps"][section].key?(key)
          merged_config["apps"][section][key] =
            deep_merge_entries(merged_config["apps"][section][key], new_entry, section)
        else
          merged_config["apps"][section][key] = new_entry
        end
      end
    end

    # Process a raw Homebrew entry into a canonical form.
    def self.merge_homebrew_entry(entry)
      token = entry["token"]
      unless token.is_a?(String) && token.match?(/^[a-z0-9]+(-[a-z0-9]+)*(@[a-z0-9.-]+)?$/)
        $stderr.puts "Warning: Invalid Homebrew token: #{token.inspect}"
        return nil
      end
      {
        "token"             => token,
        "bundle_ids"        => valid_bundle_ids(entry["bundle_ids"]),
        "unsafe_to_quit"    => entry.key?("unsafe_to_quit") ? !!entry["unsafe_to_quit"] : false,
        "quit_message"      => entry["quit_message"].is_a?(String) ? entry["quit_message"] : nil,
        "bypass_gatekeeper" => entry.key?("bypass_gatekeeper") ? !!entry["bypass_gatekeeper"] : false
      }
    end

    # Process a raw MAS entry into a canonical form.
    def self.merge_mas_entry(entry)
      app_id = entry["app_id"]
      unless app_id.is_a?(Integer) && app_id.to_s.match?(/^\d{9,10}$/)
        $stderr.puts "Warning: Invalid MAS app_id: #{app_id.inspect}"
        return nil
      end
      {
        "app_id"         => app_id,
        "name"           => entry["name"].is_a?(String) ? entry["name"] : nil,
        "bundle_ids"     => valid_bundle_ids(entry["bundle_ids"]),
        "unsafe_to_quit" => entry.key?("unsafe_to_quit") ? !!entry["unsafe_to_quit"] : false,
        "quit_message"   => entry["quit_message"].is_a?(String) ? entry["quit_message"] : nil
      }
    end

    # Validate and deduplicate each bundle ID using the regex.
    def self.valid_bundle_ids(bundle_ids)
      return [] unless bundle_ids.is_a?(Array)
      valid = []
      bundle_ids.each do |bid|
        if bid.is_a?(String) && bid.match?(/^[[:alnum:].-]+$/i)
          valid << bid
        else
          $stderr.puts "Warning: Invalid bundle id: #{bid.inspect}"
        end
      end
      valid.uniq
    end

    # Explicitly merge two entries (old and new) for the same key.
    def self.deep_merge_entries(old_entry, new_entry, section)
      merged = old_entry.dup

      if section == "homebrew"
        # Merge bundle_ids (union and deduplication).
        merged["bundle_ids"] = (old_entry["bundle_ids"] + new_entry["bundle_ids"]).uniq

        # For unsafe_to_quit: using conservative merge (true if any source is true).
        if old_entry["unsafe_to_quit"] != new_entry["unsafe_to_quit"]
          $stderr.puts("Warning: Conflict for Homebrew token #{old_entry['token']} on unsafe_to_quit – defaulting to true.")
        end
        merged["unsafe_to_quit"] = old_entry["unsafe_to_quit"] || new_entry["unsafe_to_quit"]

        # For bypass_gatekeeper, similarly.
        if old_entry["bypass_gatekeeper"] != new_entry["bypass_gatekeeper"]
          $stderr.puts("Warning: Conflict for Homebrew token #{old_entry['token']} on bypass_gatekeeper – defaulting to true if any true.")
        end
        merged["bypass_gatekeeper"] = old_entry["bypass_gatekeeper"] || new_entry["bypass_gatekeeper"]

        # For quit_message: if conflict exists, choose the new (higher priority) value and log a warning.
        if old_entry["quit_message"] && new_entry["quit_message"] && (old_entry["quit_message"] != new_entry["quit_message"])
          $stderr.puts("Warning: Conflict for Homebrew token #{old_entry['token']} on quit_message – choosing value from higher priority source.")
        end
        merged["quit_message"] = new_entry["quit_message"] || old_entry["quit_message"]

      elsif section == "mas"
        merged["bundle_ids"] = (old_entry["bundle_ids"] + new_entry["bundle_ids"]).uniq

        if old_entry["unsafe_to_quit"] != new_entry["unsafe_to_quit"]
          $stderr.puts("Warning: Conflict for MAS app_id #{old_entry['app_id']} on unsafe_to_quit – defaulting to true.")
        end
        merged["unsafe_to_quit"] = old_entry["unsafe_to_quit"] || new_entry["unsafe_to_quit"]

        if old_entry["quit_message"] && new_entry["quit_message"] && (old_entry["quit_message"] != new_entry["quit_message"])
          $stderr.puts("Warning: Conflict for MAS app_id #{old_entry['app_id']} on quit_message – choosing higher priority value.")
        end
        merged["quit_message"] = new_entry["quit_message"] || old_entry["quit_message"]

        if old_entry["name"] && new_entry["name"] && (old_entry["name"] != new_entry["name"])
          $stderr.puts("Warning: Conflict for MAS app_id #{old_entry['app_id']} on name – choosing value from higher priority source.")
        end
        merged["name"] = new_entry["name"] || old_entry["name"]
      end

      merged
    end
  end
end

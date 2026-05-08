# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: strict
# frozen_string_literal: true

require "yaml"

# ConfigLoader
#
# This module is responsible for loading and merging configuration files
# from various locations in a specific order of precedence. It supports
# combining configurations from system-wide, user-specific, and
# project-specific directories, while preserving custom merging rules.
#
# The configuration files are loaded securely using YAML.safe_load
# and merged with custom logic to handle arrays and nested hashes.
module ConfigLoader
  BASENAME = "config"
  EXTENSIONS = ["yml", "yaml"].freeze
  PROGRAM_NAME = "program_name"

  # Deep merges hashes and arrays
  # If a YAML file contains duplicate keys, only the last occurrence will be kept.
  def self.deep_merge_arrays(hash1, hash2)
    hash1.merge(hash2) do |key, old_val, new_val|
      if old_val.class != new_val.class
        puts "Type mismatch for key: #{key}, overriding with new value"
        new_val
      elsif old_val.is_a?(Hash) && new_val.is_a?(Hash)
        deep_merge_arrays(old_val, new_val)
      elsif old_val.is_a?(Array) && new_val.is_a?(Array)
        old_val | new_val # Use set union to merge arrays and remove duplicates
      # (old_val + new_val).uniq # Combine arrays and remove duplicates
      else
        new_val # Default behavior: overwrite
      end
    end
  end

  # Load and merge configuration files
  def self.load_and_merge_config(
    basename: BASENAME,
    extensions: EXTENSIONS,
    program_name: PROGRAM_NAME
  )
    # Define potential locations in inverted order of precedence
    locations = [
      "/etc/#{basename}",
      "#{Dir.home}/.config/#{program_name}/#{basename}",
      "#{Dir.home}/.#{basename}",
      "./.#{basename}",
      "./#{basename}",
    ]

    # Initialize an empty hash to store merged configurations
    merged_config = {}

    # Iterate through locations in reverse order to apply overrides
    locations.each do |location|
      extensions.each do |ext|
        file_path = "#{location}.#{ext}"
        next unless File.exist?(file_path)

        unless File.readable?(file_path)
          $stderr.puts "File is not readable: #{file_path}"
          next
        end

        begin
          $stderr.puts "Processing #{file_path}..."
          # NOTE: `YAML.safe_load_file` was introduced in Ruby 3.0.
          config = YAML.safe_load(
            File.read(file_path, encoding: "UTF-8"),
            permitted_classes: [String, Integer, Array, Hash],
            aliases:           true,
          ) || {}
          merged_config = deep_merge_arrays(merged_config, config) # Later files override earlier ones
        rescue Psych::SyntaxError => e
          puts "Syntax error in #{file_path}: #{e.message}"
        rescue => e
          puts "Failed to load #{file_path}: #{e.message}"
        end
      end
    end

    if merged_config.empty?
      puts "No config files found in the specified locations."
    else
      $stderr.puts "Merged configuration: #{merged_config}"
    end

    merged_config
  end
end

# Allow the script to run when executed directly
if __FILE__ == $PROGRAM_NAME
  puts
  puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
  # Call the ConfigLoader to load and merge configuration
  final_config = ConfigLoader.load_and_merge_config
  puts final_config
  puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
end

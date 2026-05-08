#!/usr/bin/env ruby

# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

require 'json'
require 'yaml'

# Extracts bundle IDs from various sources, filters out wildcards, deduplicates them,
# sorts them by token, and outputs a structured YAML array. 
# Tokens with no valid bundle IDs get added to a manual review list.

module BrewBundleExtractor
  class << self
    def run
      tokens_for_manual_review = []
      cask_records = extract_cask_data(tokens_for_manual_review)

      puts format_yaml(cask_records)
      print_manual_review_tokens(tokens_for_manual_review)
    end

    private

    def extract_cask_data(tokens_for_manual_review)
      brew_data = JSON.parse(`brew info --cask --installed --json=v2`)
      filtered_casks = filter_casks(brew_data)

      filtered_casks.map do |cask|
        token = cask["token"]
        bundle_ids = extract_bundle_ids(cask)

        # Filter out wildcards and deduplicate
        bundle_ids.reject! { |bid| bid.include?("*") }
        bundle_ids.uniq!.sort!

        if bundle_ids.empty?
          tokens_for_manual_review << token
          nil
        else
          { "token" => token, "bundle_ids" => bundle_ids }
        end
      end.compact.sort_by { |entry| entry["token"] }
    end

    def filter_casks(brew_data)
      brew_data["casks"].reject do |cask|
        token = cask["token"]
        artifacts = cask["artifacts"] || []

        # Exclude font casks
        token.match?(/^font-/) && artifacts.any? { |art| art.key?("font") } ||

        # Exclude casks with ONLY unwanted artifacts
        artifacts.all? do |artifact|
          unwanted = %w[qlplugin audiounitplugin colorpicker dictionary inputmethod prefpane zshcompletion fishcompletion bashcompletion]
          unwanted.any? { |key| artifact.key?(key) }
        end
      end
    end

    def extract_bundle_ids(cask)
      bundle_ids = []

      extract_uninstall_signal_ids(cask, bundle_ids)
      extract_uninstall_quit_ids(cask, bundle_ids)
      extract_app_bundle_ids(cask, bundle_ids)
      extract_artifact_app_ids(cask, bundle_ids)

      bundle_ids
    end

    def extract_uninstall_signal_ids(cask, bundle_ids)
      cask["artifacts"]&.each do |artifact|
        next unless artifact["uninstall"].is_a?(Array)
        artifact["uninstall"].each do |uninstall_entry|
          if uninstall_entry["signal"].is_a?(Array) && uninstall_entry["signal"].size >= 2
            bundle_ids << uninstall_entry["signal"][1]
          end
        end
      end
    end

    def extract_uninstall_quit_ids(cask, bundle_ids)
      cask["artifacts"]&.each do |artifact|
        next unless artifact["uninstall"].is_a?(Array)
        artifact["uninstall"].each do |uninstall_entry|
          if uninstall_entry["quit"].is_a?(Array)
            bundle_ids.concat(uninstall_entry["quit"])
          end
        end
      end
    end

    def extract_app_bundle_ids(cask, bundle_ids)
      cask["name"]&.each do |app_name|
        bundle_id = `osascript -e 'id of app "#{app_name}"' 2>/dev/null`.strip
        bundle_ids << bundle_id if !$?.exitstatus.zero? && !bundle_id.empty?
      end
    end

    def extract_artifact_app_ids(cask, bundle_ids)
      cask["artifacts"]&.each do |artifact|
        if artifact["app"].is_a?(Array)
          artifact["app"].each do |app_path|
            app_name = app_path.sub(/\.app$/, '') # Strip ".app"
            bundle_id = `osascript -e 'id of app "#{app_name}"' 2>/dev/null`.strip
            bundle_ids << bundle_id if !$?.exitstatus.zero? && !bundle_id.empty?
          end
        end
      end
    end

    def format_yaml(cask_records)
      YAML.dump(cask_records)
    end

    def print_manual_review_tokens(tokens)
      return if tokens.empty?
      
      puts "\n\033[36m#{tokens}\033[0m\n"

# copilot

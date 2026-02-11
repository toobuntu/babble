#!/usr/bin/env ruby
require 'json'
require 'yaml'

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
        bundle_ids.uniq!
        bundle_ids.sort!

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
        (token.match?(/^font-/) && artifacts.any? { |art| art.key?("font") }) ||
        
        # Exclude casks with ONLY unwanted artifacts
        artifacts.all? do |artifact|
          %w[qlplugin audiounitplugin colorpicker dictionary inputmethod 
             prefpane zshcompletion fishcompletion bashcompletion].any? do |key|
            artifact.key?(key)
          end
        end
      end
    end

    def extract_bundle_ids(cask)
      bundle_ids = []

      extract_uninstall_signal_ids(cask, bundle_ids)
      extract_app_bundle_ids(cask, bundle_ids)
      extract_artifact_app_ids(cask, bundle_ids)
      extract_uninstall_quit_ids(cask, bundle_ids)

      bundle_ids
    end

    def extract_uninstall_signal_ids(cask, bundle_ids)
      cask["artifacts"]&.each do |artifact|
        next unless (uninstall_entries = artifact["uninstall"])
        Array(uninstall_entries).each do |entry|
          next unless (signals = entry["signal"])
          bundle_ids << signals[1] if signals.is_a?(Array) && signals.size >= 2
        end
      end
    end

    def extract_uninstall_quit_ids(cask, bundle_ids)
      cask["artifacts"]&.each do |artifact|
        next unless (uninstall_entries = artifact["uninstall"])
        Array(uninstall_entries).each do |entry|
          next unless (quits = entry["quit"])
          bundle_ids.concat(Array(quits))
        end
      end
    end

    def extract_app_bundle_ids(cask, bundle_ids)
      cask["name"]&.each do |app_name|
        next if app_name.empty?
        bundle_id = `osascript -e 'id of app "#{app_name}"' 2>/dev/null`.strip
        bundle_ids << bundle_id if $?.success? && !bundle_id.empty?
      end
    end

    def extract_artifact_app_ids(cask, bundle_ids)
      cask["artifacts"]&.each do |artifact|
        next unless (apps = artifact["app"])
        Array(apps).each do |entry|
          # Handle both string and hash formats ("app" => "Foo.app" vs "app" => { "target" => "Foo.app" })
          app_path = entry.is_a?(Hash) ? entry["target"] : entry
          next if app_path.to_s.empty?
    
          mod_app = app_path.sub(/\.app$/i, '')
          bundle_id = `osascript -e 'id of app "#{mod_app}"' 2>/dev/null`.strip
          bundle_ids << bundle_id if $?.success? && !bundle_id.empty?
        end
      end
    end

    def format_yaml(cask_records)
      # Generate raw YAML
      yaml_str = Psych.dump(cask_records, indentation: 2)

      # Remove Psych's default document header and apply ANSI color
      # styling for readability
      yaml_str.sub(/\A---\n/, "").then { |s| colorize_yaml(s) }
    end

    def colorize_yaml(yaml_str)
      yaml_str.lines.map do |line|
        case line
        # Color list headers (i.e., "- token: zoom")
        when /^(\s*)- (token): (.*)/
          "#{$1}- \e[36m#{$2}:\e[0m \e[32m#{$3}\e[0m"
        # Color top-level keys (i.e., "bundle_ids:")
        when /^(\s*)(bundle_ids):/
          "#{$1}\e[36m#{$2}:\e[0m" # cyan
        # Color nested array items (e.g., "  - us.zoom.xos") and
        # normalize array item indentation like yq's pretty print
        when /^(\s*)- (.*)/
          "#{$1 + "  "}- \e[32m#{$2}\e[0m" # green
        # Leave other lines untouched
        else
          line
        end
      end.join("\n")
    end

    def print_manual_review_tokens(tokens)
      return if tokens.empty?

      sorted_tokens = tokens.sort.uniq
      puts "\n\033[1;31mTokens needing manual review:\033[0m" # red
      sorted_tokens.each { |t| puts "\033[36m#{t}\033[0m" }
    end
  end
end

BrewBundleExtractor.run if __FILE__ == $0

# perplexity

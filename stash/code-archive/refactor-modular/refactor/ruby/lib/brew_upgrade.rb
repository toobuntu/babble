#!/usr/bin/env ruby

# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: strict
# frozen_string_literal: true

require "English"
require "yaml"
require "open3"
require "json"
require_relative "../ui/waiter"
require_relative "./utils/bundle_launcher"

# BrewUpgrade
#
# The BrewUpgrade module automates the process of upgrading Homebrew
# formulae and casks. It provides methods for listing outdated packages,
# upgrading them, and managing related tasks. A key feature is the ability
# to read cask tokens and their associated Bundle IDs from a configuration
# file, automatically quitting those applications before the upgrade and
# reopening them once the upgrade is complete.
#
# Usage:
#   BrewUpgrade.upgrade_packages
#
module BrewUpgrade
  CONFIG_FILE = "unified-config.yml"

  # Check if yq is available on the system
  def self.yq_available?
    ENV["PATH"].split(File::PATH_SEPARATOR).any? do |directory|
      File.executable?(File.join(directory, "yq"))
    end
  end

  # Validate bundle ID according to Apple's specifications
  def self.valid_bundle_id?(bundle_id)
    bundle_id.match?(/^[[:alnum:].-]+$/i)
  end

  # Validate Homebrew token, including pinned versions and channels
  def self.valid_homebrew_token?(token)
    token.match?(/^[a-z0-9]+(-[a-z0-9]+)*(@[a-z0-9.-]+)?$/)
  end

  # Check if a token listed in the configuration file is installed
  def self.token_installed?(token)
    stdout, _, status = Open3.capture3("brew list")
    return stdout.include?(token) if status.success?

    stdout, _, status = Open3.capture3("mas list")
    stdout.include?(token) if status.success?
  end

  def self.test_valid_bundle_id
    valid_cases = ["com.example.app", "com.example-app.sub", "COM.EXAMPLE.APP"]
    invalid_cases = ["com.example.app!", "com.example.app_sub", "com.example.app/sub"]

    valid_cases.each do |case_|
      raise "Failed for valid Bundle ID case: #{case_}" unless BrewUpgrade.valid_bundle_id?(case_)
    end

    invalid_cases.each do |case_|
      raise "Failed for invalid Bundle ID case: #{case_}" if BrewUpgrade.valid_bundle_id?(case_)
    end

    puts "All Bundle ID validation tests passed."
  end

  def self.test_valid_homebrew_token
    valid_cases = ["example-token", "token", "token-with-hyphens", "token@1.2.3", "token@nightly"]
    invalid_cases = ["Token", "TOKEN", "token_with_underscore", "token@invalid!", "token@1.2@3", "-token", "token-"]

    valid_cases.each do |case_|
      raise "Failed for valid Homebrew token case: #{case_}" unless BrewUpgrade.valid_homebrew_token?(case_)
    end

    invalid_cases.each do |case_|
      raise "Failed for invalid Homebrew token case: #{case_}" if BrewUpgrade.valid_homebrew_token?(case_)
    end

    puts "All Homebrew token validation tests passed."
  end

  # Validate and clean the configuration
  def self.validate_config(raw_config)
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
        valid_entry["unsafe_to_quit"] ||= new_value
      end

      if entry.key?("quit_message")
        valid_entry["quit_message"]
        entry["quit_message"].to_s
        if existing_value && (existing_value != new_value)
          conflicts << "Conflicting 'quit_message' values for cask #{token}"
        end
        valid_entry["quit_message"] ||= new_value.to_s
      end

      # Append correctly to the nested array:
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
        valid_mas_entry["unsafe_to_quit"] ||= new_value
      end

      if entry.key?("quit_message")
        if valid_mas_entry["quit_message"] && (valid_mas_entry["quit_message"] != entry["quit_message"])
          conflicts << "Conflicting 'quit_message' values for MAS app #{app_id} - #{entry["name"]}"
        end
        valid_mas_entry["quit_message"] ||= entry["quit_message"].to_s
      end

      # Append correctly to the nested array:
      valid_config["apps"]["mas"] << valid_mas_entry
    end

    [valid_config, conflicts, validation_errors, structural_issues]
  end

  def self.load_and_validate_configuration(config_file)
    raw_config = {}
    if File.exist?(config_file)
      begin
        raw_config = YAML.load_file(config_file)
      rescue Psych::SyntaxError => e
        $stderr.puts "Warning: Failed to parse YAML configuration file. #{e.message}"
        $stderr.puts "Proceeding with empty configuration."
      end
    end

    # Ensure that 'homebrew' and 'mas' are arrays
    raw_config["apps"] ||= {}
    raw_config["apps"]["homebrew"] ||= []
    raw_config["apps"]["mas"] ||= []

    config, conflicts, validation_errors, structural_issues = BrewUpgrade.validate_config(raw_config)

    $stderr.puts "\nraw config=#{raw_config}"

    if config.empty?
      $stderr.puts "Warning: No valid entries found in the configuration file. Proceeding with default behavior."
      config = raw_config.dig("apps", "homebrew") || [] # Use raw_config if validated config is empty
    else
      unless validation_errors.empty?
        $stderr.puts "Validation Errors:"
        validation_errors.each { |error| $stderr.puts "  - #{error}" }
      end

      unless structural_issues.empty?
        $stderr.puts "Structural Issues:"
        structural_issues.each { |issue| $stderr.puts "  - #{issue}" }
      end

      unless conflicts.empty?
        $stderr.puts "Conflicts:"
        conflicts.each { |conflict| $stderr.puts "  - #{conflict}" }
        $stderr.puts "Conflicts have been resolved by merging entries and using conservative settings."
      end
    end

    $stderr.puts "\nconfig=#{config}"
    [config, conflicts, validation_errors, structural_issues]
  end

  def self.check_duplicates(data)
    # Check for duplicates under 'homebrew'
    homebrew_tokens = data.dig("apps", "homebrew")&.map { |app| app["token"] } || []
    homebrew_duplicates = homebrew_tokens.select { |token| homebrew_tokens.count(token) > 1 }.uniq

    # Check for duplicates under 'mas'
    mas_app_ids = data.dig("apps", "mas")&.map { |app| app["app_id"].to_s } || []
    mas_duplicates = mas_app_ids.select { |app_id| mas_app_ids.count(app_id) > 1 }.uniq

    [homebrew_duplicates, mas_duplicates]
  end

  def self.reorganize_config_file(file_path)
    return false unless File.exist?(file_path)

    if BrewUpgrade.yq_available?
      original_content = File.read(file_path)
      begin
        # Sort by token or app_id and sort bundle_ids
        sorted_content = `yq eval '
  .apps.homebrew |= sort_by(.token) |
  .apps.mas |= sort_by(.name) |
  (.apps.homebrew[].bundle_ids |= sort) |
  (.apps.mas[].bundle_ids |= sort)
' #{file_path}`
        data = YAML.safe_load(sorted_content)

        # Check for duplicates
        homebrew_duplicates, mas_duplicates = check_duplicates(data)

        if homebrew_duplicates.any? || mas_duplicates.any?
          $stderr.puts "\033[33mWarning:\033[0m Duplicates detected in YAML file."
          $stderr.puts "  Please manually inspect and deduplicate the following entries:\n"
          if homebrew_duplicates.any?
            puts "  \033[1mHomebrew duplicates:\033[0m"
            homebrew_duplicates.each do |token|
              duplicate_entries = data["apps"]["homebrew"].select { |app| app["token"] == token }
              duplicate_entries.each do |entry|
                puts "    #{YAML.dump(entry).gsub(/^/, "    ")}"
              end
            end
          end
          if mas_duplicates.any?
            puts "  \033[1mMAS duplicates:\033[0m"
            mas_duplicates.each do |app_id|
              duplicate_entries = data["apps"]["mas"].select { |app| app["app_id"] == app_id }
              duplicate_entries.each do |entry|
                puts "    #{YAML.dump(entry).gsub(/^/, "    ")}"
              end
            end
          end
          exit 1
        end

        if $CHILD_STATUS.success?
          if original_content == sorted_content
            $stderr.puts "Configuration file is already properly organized."
            false
          else
            File.write(file_path, sorted_content)
            $stderr.puts "Configuration file has been reorganized."
            true
          end
        else
          $stderr.puts "Error: yq command failed."
          false
        end
      rescue => e
        $stderr.puts "Error executing yq: #{e.message}"
        false
      end
    else
      $stderr.puts "Note: Install 'yq' for enhanced config file organization capabilities."
      false
    end
  end

  def self.update_if_needed
    system("brew", "update-if-needed")
  end

  def self.display_outdated_packages
    puts "\nListing installed packages which are outdated..."
    puts "Would run `brew outdated`"
    Waiter.waiter("run_command")

    # Disabling auto-updates is safe in this controlled workflow
    # but is not recommended generally, as it might lead to a broken
    # configuration (e.g., when adding new taps).
    auto_update_disabled = "HOMEBREW_NO_AUTO_UPDATE=1"
    cmd = "#{auto_update_disabled} brew outdated --greedy-auto-updates --fetch-HEAD --verbose"
    stdout, status = Open3.capture2(cmd)

    if status.success?
      if stdout.strip.empty?
        return false # No outdated packages, allowing early abort
      else
        puts "Outdated packages:"
        puts stdout
        return true
      end
    else
      $stderr.puts "Error running brew outdated command."
      return false
    end
    # if status.success?
    #   unless stdout.strip.empty?
    #     puts "Outdated packages:"
    #     puts stdout
    #   end
    # else
    #   $stderr.puts "Error running brew outdated command."
    # end
  end

  def self.upgrade_packages(casks_to_quit_and_reopen, initially_running_apps)
    puts "\nPreparing to upgrade the outdated packages..."
    puts "Would run `brew upgrade`"
    Waiter.waiter("run_command")

    if casks_to_quit_and_reopen.any?
      quit_apps(casks_to_quit_and_reopen, initially_running_apps)
    end

    # Disabling auto-updates is safe in this controlled workflow
    # but is not recommended generally, as it might lead to a broken
    # configuration (e.g., when adding new taps).
    auto_update_disabled = { "HOMEBREW_NO_AUTO_UPDATE" => "1" }
    success = system(defined?(auto_update_disabled) ? auto_update_disabled : {}, "brew", "upgrade", "--greedy-auto-updates", "--fetch-HEAD", "--display-times")
    $stderr.puts "Warning: Failed to upgrade packages." unless success
    success
  end

  def self.quit_apps(casks_to_quit_and_reopen, initially_running_apps)
    if casks_to_quit_and_reopen.any?
      puts "The following casks are scheduled for upgrade and will require quitting/reopening:\n  " \
           "#{casks_to_quit_and_reopen.map { |entry| entry["token"] }.join("\n  ")}"

      # Quit all associated apps if they are running
      casks_to_quit_and_reopen.each do |entry|
        bundle_ids = entry["bundle_ids"].is_a?(Array) ? entry["bundle_ids"] : []
        bundle_ids.each do |bundle_id|
          if initially_running_apps.include?(bundle_id)
            puts "Quitting #{bundle_id}..."
            quit_app(bundle_id, entry)
          else
            $stderr.puts "#{bundle_id} is not running, skipping quit."
          end
        end
      end
    end
  end


  def self.reopen_apps(casks_to_quit_and_reopen, initially_running_apps)
    # Reopen applications after upgrade (if they were previously running)
    if casks_to_quit_and_reopen.any?
      casks_to_quit_and_reopen.each do |entry|
        entry["bundle_ids"].each do |bundle_id|
          if initially_running_apps.include?(bundle_id)
            puts "Reopening #{bundle_id}..."
            open_app(bundle_id)
          else
            $stderr.puts "#{bundle_id} was not running, skipping reopen."
          end
        end
      end
    end
  end


  def self.outdated_casks_json
    # Disabling auto-updates is safe in this controlled workflow
    # but is not recommended generally, as it might lead to a broken
    # configuration (e.g., when adding new taps).
    auto_update_disabled = "HOMEBREW_NO_AUTO_UPDATE=1"
    cmd = "#{auto_update_disabled} brew outdated --greedy-auto-updates --fetch-HEAD --json=v2"
    stdout, status = Open3.capture2(cmd)

    if status.success?
      begin
        json_data = JSON.parse(stdout)
        # Extract only cask tokens if "casks" exists and is an array
        json_data["casks"].is_a?(Array) ? json_data["casks"].map { |c| c["name"] } : []
      rescue JSON::ParserError => e
        $stderr.puts "Error parsing JSON output from brew: #{e.message}"
        []
      end
    else
      $stderr.puts "Error running brew outdated command."
      []
    end
  end

  def self.set_running_apps
    # Get the list of running GUI apps and their bundle IDs using lsappinfo
    stdout, status = Open3.capture2(
      "/usr/bin/lsappinfo list | " \
      "/usr/bin/awk -F'\"' '/bundleID/{print $2}' | " \
      "/usr/bin/sort -u",
    )

    if status.success?
      stdout.strip.empty? ? [] : stdout.split("\n").compact
    else
      $stderr.puts "Error getting running apps."
      []
    end
  end

  def self.quit_app(bundle_id, config_entry)
    if config_entry["unsafe_to_quit"]
      puts config_entry["quit_message"] || "Please save your work in the application before continuing."
      puts "Press Enter when ready to quit the application."
      gets
    end

    jxa_script = <<-EOS
    var app;
    try {
        var app = Application("#{bundle_id}");
        if (app.running()) {
            app.quit();
            $.NSFileHandle.fileHandleWithStandardOutput.writeData(
                $.NSString.alloc.initWithUTF8String("Successfully quit application with Bundle ID: #{bundle_id}.\\n").dataUsingEncoding($.NSUTF8StringEncoding)
            );
        } else {
            $.NSFileHandle.fileHandleWithStandardError.writeData(
                $.NSString.alloc.initWithUTF8String("Application with Bundle ID: #{bundle_id} is not running.\\n").dataUsingEncoding($.NSUTF8StringEncoding)
            );
        }
    } catch (error) {
        $.NSFileHandle.fileHandleWithStandardError.writeData(
            $.NSString.alloc.initWithUTF8String("Error while processing Bundle ID: #{bundle_id}. " + error.toString() + "\\n").dataUsingEncoding($.NSUTF8StringEncoding)
        );
    }
    undefined;
    EOS

    stdout, stderr, = Open3.capture3("osascript -l JavaScript", stdin_data: jxa_script)
    BrewUpgrade.handle_quit_result(stdout, stderr, bundle_id)
  end

  def self.handle_quit_result(stdout, stderr, bundle_id)
    if stdout.include?("Successfully quit application")
      puts "Successfully quit application: #{bundle_id}"
      return true
    end

    if stderr.include?("is not running")
      puts "Application #{bundle_id} was not running."
      return false
    end

    unless stderr.empty?
      $stderr.puts "Warning: Failed to quit application with Bundle ID #{bundle_id} - #{stderr.strip}"
      return false
    end

    return if stdout.empty?

    $stderr.puts "Warning: Unexpected output while processing Bundle ID #{bundle_id} - #{stdout.strip}"
    false
  end

  def self.open_app(bundle_id, tries: 1)
    $stderr.puts "starting the open_app method..."
    # $stderr.puts "  parsed bundle_id: #{bundle_id.inspect}"
    # $stderr.puts "  bytes: #{bundle_id.bytes.to_a}"
    # $stderr.puts "  encoding: #{bundle_id.encoding} valid?: #{bundle_id.valid_encoding?}"
    $stderr.puts "  time: #{Time.now.utc.iso8601(6)} uid: #{Process.uid}" # env: #{ENV.slice('USER','HOME','LANG').inspect}"
    # Launch with retry to resolve a potential race between the lookup and the LaunchServices state (transient/unresolved entry)
    attempts = 0
    begin
      attempts += 1
      MacUtils::BundleLauncher.launch(bundle_id, timeout: 10)
    rescue => e
      raise if attempts >= tries
      sleep 0.15
      retry
    end
    # success = system("/usr/bin/open", "-g", "-b", bundle_id)

    # return if success

    # $stderr.puts "Warning: Failed to open application with Bundle ID #{bundle_id}."
  end

  # def self.upgrade_packages
  #   # Upgrade all outdated packages at once with specified options
  #   success = system("brew", "upgrade", "--greedy-auto-updates", "--fetch-HEAD", "--display-times")

  #   $stderr.puts "Warning: Failed to upgrade packages." unless success

  #   success # Return whether the upgrade was successful or not.
  # end

  # Main logic
  def self.run_upgrade_process
    # Run validation tests
    test_valid_bundle_id
    test_valid_homebrew_token

    # Attempt to reorganize the configuration file for better readability
    reorganize_config_file(CONFIG_FILE)

    # Load and validate configuration
    config, =
      load_and_validate_configuration(CONFIG_FILE)
    $stderr.puts "\nLoaded config: #{config.class} - #{config.inspect}"

    # Refresh metadata
    update_if_needed

    # Display nicely formatted information about outdated packages
    if display_outdated_packages
      $stderr.puts "There are outdated packages to upgrade."
    else
      puts "No upgrades needed; everything is up to date."
      return
    end

    # Get outdated casks and running apps
    outdated_cask_tokens = outdated_casks_json
    $stderr.puts "\noutdated cask tokens=#{outdated_cask_tokens}"
    initially_running_apps = set_running_apps
    $stderr.puts "\nrunning apps=#{initially_running_apps}"

    # Extract homebrew entries correctly:
    homebrew_entries = config.dig("apps", "homebrew") || []

    # Determine which casks need to be quit and reopened
    casks_to_quit_and_reopen = homebrew_entries.select do |entry|
      $stderr.puts "\nchecking entry: #{entry}"
      $stderr.puts("  outdated_cask_tokens includes token? " + outdated_cask_tokens&.include?(entry["token"]).to_s)
      $stderr.puts("  bundle_ids is an array? " + entry["bundle_ids"].is_a?(Array).to_s)
      $stderr.puts("  initially_running_apps includes bundle_id? " + entry["bundle_ids"].any? { |bundle_id| initially_running_apps&.include?(bundle_id) }.to_s)
      outdated_cask_tokens&.include?(entry["token"]) &&
        entry["bundle_ids"].is_a?(Array) &&
        entry["bundle_ids"].any? { |bundle_id| initially_running_apps&.include?(bundle_id) }
    end

    # # Determine which casks need to be quit and reopened
    # $stderr.puts "\nhomebrew section: #{config.dig("apps", "homebrew")}"
    # casks_to_quit_and_reopen = config.dig("apps", "homebrew").map do |token, entry|
    #   { "token" => token, "bundle_ids" => entry["bundle_ids"], "unsafe_to_quit" => entry["unsafe_to_quit"] }
    # end.select do |entry|
    #   $stderr.puts "\nChecking entry: #{entry["token"]}"
    #   token_match = outdated_cask_tokens&.include?(entry["token"])
    #   $stderr.puts "  Token match: #{token_match}"

    #   bundle_ids_valid = entry["bundle_ids"].is_a?(Array)
    #   $stderr.puts "  Bundle IDs valid: #{bundle_ids_valid}"

    #   bundle_id_running = entry["bundle_ids"].any? { |bundle_id| running_apps&.include?(bundle_id) }
    #   $stderr.puts "  At least one bundle ID running: #{bundle_id_running}"

    #   bundle_id_running
    #   # token_match && bundle_ids_valid && bundle_id_running
    #   # outdated_cask_tokens&.include?(entry["token"]) &&
    #   #   entry["bundle_ids"].is_a?(Array) &&
    #   #   entry["bundle_ids"].any? { |bundle_id| running_apps&.include?(bundle_id) }
    # end || []
    $stderr.puts "\ncasks to quit and reopen=#{casks_to_quit_and_reopen.inspect}"
    # exit 4

    # if casks_to_quit_and_reopen.any?
    #   puts "The following casks are scheduled for upgrade and will require quitting/reopening:\n  " \
    #        "#{casks_to_quit_and_reopen.map { |entry| entry["token"] }.join("\n  ")}"

    #   # Quit all associated apps if they are running
    #   casks_to_quit_and_reopen.each do |entry|
    #     bundle_ids = entry["bundle_ids"].is_a?(Array) ? entry["bundle_ids"] : []
    #     bundle_ids.each do |bundle_id|
    #       if running_apps.include?(bundle_id)
    #         puts "Quitting #{bundle_id}..."
    #         quit_app(bundle_id, entry)
    #       else
    #         $stderr.puts "#{bundle_id} is not running, skipping quit."
    #       end
    #     end
    #   end
    # end

    # Upgrade all outdated packages regardless of whether they are in the config file or not.
    # puts "Upgrading all outdated packages..."
    upgraded_successfully = upgrade_packages(casks_to_quit_and_reopen, initially_running_apps)

    # Reopen applications after upgrade (if they were previously running)
    if casks_to_quit_and_reopen.any?
      reopen_apps(casks_to_quit_and_reopen, initially_running_apps)
      # casks_to_quit_and_reopen.each do |entry|
      #   entry["bundle_ids"].each do |bundle_id|
      #     if running_apps.include?(bundle_id)
      #       puts "Reopening #{bundle_id}..."
      #       open_app(bundle_id)
      #     else
      #       $stderr.puts "#{bundle_id} was not running, skipping reopen."
      #     end
      #   end
      # end
    end

    # Final message based on whether any upgrades were performed.
    puts "Upgrade process complete." if upgraded_successfully
    puts "Reopened necessary applications after upgrade." if casks_to_quit_and_reopen.any?
    # if upgraded_successfully || casks_to_quit_and_reopen.any?
    #   puts "Upgrade process complete."
    # else
    #   puts "No upgrades were needed; everything is up to date."
    # end
  rescue => e
    puts "Error: #{e.message}"
    exit 1
  end

  # Call main logic
  # BrewUpgrade.run_upgrade_process

  # begin
  #
  #   # Extract homebrew entries correctly:
  #   homebrew_entries = config.dig("apps", "homebrew") || []
  #
  #   # Determine which casks need to be quit and reopened
  #   casks_to_quit_and_reopen = homebrew_entries.select do |entry|
  #     $stderr.puts "\nchecking entry: #{entry}"
  #     outdated_cask_tokens&.include?(entry["token"]) &&
  #       entry["bundle_ids"].is_a?(Array) &&
  #       entry["bundle_ids"].any? { |bundle_id| running_apps&.include?(bundle_id) }
  #   end
  #
  #   # # Determine which casks need to be quit and reopened
  #   # $stderr.puts "\nhomebrew section: #{config.dig("apps", "homebrew")}"
  #   # casks_to_quit_and_reopen = config.dig("apps", "homebrew").map do |token, entry|
  #   #   { "token" => token, "bundle_ids" => entry["bundle_ids"], "unsafe_to_quit" => entry["unsafe_to_quit"] }
  #   # end.select do |entry|
  #   #   $stderr.puts "\nChecking entry: #{entry["token"]}"
  #   #   token_match = outdated_cask_tokens&.include?(entry["token"])
  #   #   $stderr.puts "  Token match: #{token_match}"
  #
  #   #   bundle_ids_valid = entry["bundle_ids"].is_a?(Array)
  #   #   $stderr.puts "  Bundle IDs valid: #{bundle_ids_valid}"
  #
  #   #   bundle_id_running = entry["bundle_ids"].any? { |bundle_id| running_apps&.include?(bundle_id) }
  #   #   $stderr.puts "  At least one bundle ID running: #{bundle_id_running}"
  #
  #   #   bundle_id_running
  #   #   # token_match && bundle_ids_valid && bundle_id_running
  #   #   # outdated_cask_tokens&.include?(entry["token"]) &&
  #   #   #   entry["bundle_ids"].is_a?(Array) &&
  #   #   #   entry["bundle_ids"].any? { |bundle_id| running_apps&.include?(bundle_id) }
  #   # end || []
  #   $stderr.puts "\ncasks to quit and reopen=#{casks_to_quit_and_reopen.inspect}"
  #   # exit 4
  #
  #   if casks_to_quit_and_reopen.any?
  #     puts "The following casks are scheduled for upgrade and will require quitting/reopening:\n  " \
  #          "#{casks_to_quit_and_reopen.map { |entry| entry["token"] }.join("\n  ")}"
  #
  #     # Quit all associated apps if they are running
  #     casks_to_quit_and_reopen.each do |entry|
  #       bundle_ids = entry["bundle_ids"].is_a?(Array) ? entry["bundle_ids"] : []
  #       bundle_ids.each do |bundle_id|
  #         if running_apps.include?(bundle_id)
  #           puts "Quitting #{bundle_id}..."
  #           BrewUpgrade.quit_app(bundle_id, entry)
  #         else
  #           $stderr.puts "#{bundle_id} is not running, skipping quit."
  #         end
  #       end
  #     end
  #   end
  #
  #   # Upgrade all outdated packages regardless of whether they are in the config file or not.
  #   puts "Upgrading all outdated packages..."
  #   upgraded_successfully = BrewUpgrade.upgrade_packages
  #
  #   # Reopen applications after upgrade (if they were previously running)
  #   if casks_to_quit_and_reopen.any?
  #     casks_to_quit_and_reopen.each do |entry|
  #       entry["bundle_ids"].each do |bundle_id|
  #         if running_apps.include?(bundle_id)
  #           puts "Reopening #{bundle_id}..."
  #           BrewUpgrade.open_app(bundle_id)
  #         else
  #           $stderr.puts "#{bundle_id} was not running, skipping reopen."
  #         end
  #       end
  #     end
  #   end
  #
  #   # Final message based on whether any upgrades were performed.
  #   if upgraded_successfully || casks_to_quit_and_reopen.any?
  #     puts "Upgrade process complete."
  #   else
  #     puts "No upgrades were needed; everything is up to date."
  #   end
  # rescue => e
  #   puts "Error: #{e.message}"
  #   exit 1
  # end
end

# Allow the script to run when executed
if __FILE__ == $PROGRAM_NAME

  puts
  puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
  # Call the main method to start the test
  BrewUpgrade.run_upgrade_process
  puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
end

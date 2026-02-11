# typed: strict
# frozen_string_literal: true

require "open3"

# BrewUpdate
#
# The BrewUpdate module automates the process of updating Homebrew.
# It includes methods for printing descriptions of new formulae and
# casks, as well as opening URLs to display release notes and
# changelogs for new Homebrew versions.
#
# Usage:
#   BrewUpdate.open_url(url)
#   BrewUpdate.update_brew
#
module BrewUpdate
  # Helper method to strip ANSI escape sequences
  def self.strip_ansi_escape_sequences(text)
    text.gsub(%r{\e\[[0-9:;<=>?]*[ !\"#$%&'()*+,-./]*[@A-Za-z\\^_`{|}~]}, "")
  end

  def self.open_url(url)
    # Determine the browser to use for opening URLs, prioritizing
    # HOMEBREW_BROWSER, falling back to BROWSER if not set, and
    # defaulting to nil.
    browser = ENV["HOMEBREW_BROWSER"] || ENV.fetch("BROWSER", nil)

    if browser
      # If HOMEBREW_BROWSER or BROWSER is set, use it
      %x|"#{browser}" '#{url}'|
      # system("#{browser} '#{url}'")
    else
      # Otherwise, fall back to the system default browser
      %x|/usr/bin/open -u '#{url}'|
      # system("/usr/bin/open -u '#{url}'")
    end
  end

  def self.update_brew
    # Arrays to store new formulae and casks
    formulae = []
    casks = []
    # Variables to store URLs for release notes and changelogs
    release_notes = nil
    changelog = nil
    # Flags to indicate whether we are within a relevant section
    in_formulae_section = false
    in_casks_section = false

    # Force color output for better readability and ensure API data update
    ENV["HOMEBREW_COLOR"] = "1"
    ENV["HOMEBREW_FORCE_API_AUTO_UPDATE"] = "1"

    # Execute 'brew update' and process the output
    puts("Would run `brew update`")
    Open3.popen2e("brew update") do |_stdin, stdout_and_stderr, _wait_thr|
      stdout_and_stderr.each do |line|
        puts line # Print each line of the output for visibility

        cleaned_line = strip_ansi_escape_sequences(line.strip)

        case cleaned_line
        when /^==>.*New Formulae/
          # Start of new formulae section
          in_formulae_section = true
          in_casks_section = false
        when /^==>.*New Casks/
          # Start of new casks section
          in_formulae_section = false
          in_casks_section = true
        when /^==>.*(Outdated|Renamed|Deleted|Modified)/, /^You have/, /^Already up-to-date$/
          # End of relevant sections or start of irrelevant sections
          in_formulae_section = false
          in_casks_section = false
        else
          # Collect lines in the relevant section, skipping empty lines
          if in_formulae_section
            formulae << cleaned_line unless cleaned_line.empty?
          elsif in_casks_section
            casks << cleaned_line unless cleaned_line.empty?
          end
        end

        # Capture URLs for release notes and changelogs, cleaning up ANSI escape sequences
        if %r{https://brew\.sh/blog/\d+\.\d+\.\d+}.match?(cleaned_line)
          release_notes = cleaned_line.strip
        elsif line.include?("https://github.com/Homebrew/brew/releases/tag")
          changelog = cleaned_line.strip
        end
      end
    end

    # Print descriptions of new formulae
    unless formulae.empty?
      puts "\n\033[36m⨀=> \033[0m\033[1mDescriptions of New Formulae\033[0m\n"
      formulae.each do |formula|
        system("brew", "desc", "--formula", formula.to_s)
      end
    end

    # Print descriptions of new casks
    unless casks.empty?
      puts "\n\033[36m⨀=> \033[0m\033[1mDescriptions of New Casks\033[0m\n"
      casks.each do |cask|
        system("brew", "desc", "--cask", cask.to_s)
      end
    end

    # Open release notes URL in the browser if available
    if release_notes
      puts "\n⨀=> New Homebrew version: opening release notes in web browser..."
      system("open", release_notes)
    end

    # Open changelog URL in the browser if available
    return unless changelog

    puts "\n⨀=> New Homebrew patch version: opening changelog in web browser..."
    system("open", changelog)
  end

  #   def self.update_brew
  #     # $stderr.puts "Debug: update_brew called"
  #     formulae = []
  #     casks = []
  #     release_notes = nil
  #     changelog = nil
  #     in_formulae_section = false
  #     in_casks_section = false
  #
  #     # Force color output on non-TTY outputs
  #     ENV["HOMEBREW_COLOR"] = "1"
  #     # Update the Homebrew API formula or cask data even if HOMEBREW_NO_AUTO_UPDATE is set
  #     ENV["HOMEBREW_FORCE_API_AUTO_UPDATE"] = "1"
  #
  #     Open3.popen2e("brew update") do |_stdin, stdout_and_stderr, _wait_thr|
  #       stdout_and_stderr.each do |line|
  #         puts line # Print the line to the screen
  #
  #         case line.strip
  #         when /^==>.*New Formulae/
  #           # Start of new formulae section
  #           in_formulae_section = true
  #           in_casks_section = false
  #         when /^==>.*New Casks/
  #           # Start of new casks section
  #           in_formulae_section = false
  #           in_casks_section = true
  #         when /^==>.*(Outdated|Renamed|Deleted|Modified)/, /^You have/, /^Already up-to-date$/
  #           # End of relevant sections or irrelevant lines
  #           in_formulae_section = false
  #           in_casks_section = false
  #
  #
  #
  #
  #         # Match blog URLs
  #         when %r{https://brew\.sh/blog/\d+\.\d+\.\d+}
  #           # Extract release notes URL
  #           # Remove ANSI escape sequences (color, boldface, etc.)
  #           # Remove control characters (SOH, STX)
  #           # See https://en.wikipedia.org/wiki/ANSI_escape_code#Control_Sequence_Introducer_commands
  #           release_notes = line.strip.gsub(%r{\e\[[0-9:;<=>?]*[ !\"#$%&'()*+,-./]*[@A-Za-z\\^_`{|}~]}, "").strip
  #         # gsub(/\x01?(\x1B\(B)?\x1B\[([0-9;]*)?[JKmsu]\x02?/, '').strip
  #         # Match GitHub release tag URLs
  #         when %r{https://github\.com/Homebrew/brew/releases/tag}
  #           # Extract changelog URL
  #           # Remove ANSI escape sequences (color, boldface, etc.)
  #           # Remove control characters (SOH, STX)
  #           changelog = line.strip.gsub(%r{\e\[[0-9:;<=>?]*[ !\"#$%&'()*+,-./]*[@A-Za-z\\^_`{|}~]}, "").strip
  #           # gsub(/\x01?(\x1B\(B)?\x1B\[([0-9;]*)?[JKmsu]\x02?/, '').strip
  #         else
  #           if in_formulae_section
  #             # Collect new formula names
  #             formulae << line.strip
  #           elsif in_casks_section
  #             # Collect new cask names
  #             casks << line.strip
  #           end
  #         end
  #       end
  #     end
  #
  #     # Print descriptions of new formulae
  #     unless formulae.empty?
  #       puts "\n\033[36m⨀=> \033[0m\033[1mDescriptions of New Formulae\033[0m\n"
  #       formulae.each do |formula|
  #         system("brew", "desc", "--formula", formula.to_s)
  #       end
  #     end
  #
  #     # Print descriptions of new casks
  #     unless casks.empty?
  #       puts "\n\033[36m⨀=> \033[0m\033[1mDescriptions of New Casks\033[0m\n"
  #       casks.each do |cask|
  #         system("brew", "desc", "--cask", cask.to_s)
  #       end
  #     end
  #
  #     # Open URLs for new Homebrew versions
  #     if release_notes
  #       puts "\n⨀=> New Homebrew version: opening release notes in web browser..."
  #       open_url(release_notes)
  #       # system("open '#{release_notes}'")
  #     end
  #
  #     return unless changelog
  #
  #     puts "\n⨀=> New Homebrew patch version: opening changelog in web browser..."
  #     open_url(changelog)
  #     # system("open '#{changelog}'")
  #   end
end

# Execute the update_brew method if the script is run directly
# BrewUpdate.update_brew if __FILE__ == $PROGRAM_NAME
if __FILE__ == $PROGRAM_NAME

  puts
  # Print the current date and time in the same format as /bin/date.
  # Here's a breakdown of the format string:
  # %a - Abbreviated weekday name (e.g., Mon)
  # %b - Abbreviated month name (e.g., Mar)
  # %e - Day of the month, blank-padded (e.g., 3)
  # %H - Hour of the day, 24-hour clock (e.g., 08)
  # %M - Minute of the hour (e.g., 49)
  # %S - Second of the minute (e.g., 45)
  # %Z - Time zone name (e.g., EST)
  # %Y - Year with century (e.g., 2025)
  puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
  # system("/bin/date")
  BrewUpdate.update_brew
  puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
end

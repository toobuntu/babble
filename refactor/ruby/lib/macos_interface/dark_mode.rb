# typed: strict
# frozen_string_literal: true

# macos_interface/dark_mode.rb

# The MacOSInterface module provides macOS-related utility classes for
# interacting with macOS-specific settings and features.
module MacOSInterface
  # Determines whether macOS is currently in dark mode.
  class DarkMode
    # Returns true if the system is in dark mode, otherwise false.
    def self.enabled?
      # The `defaults` command checks the global "AppleInterfaceStyle" key.
      # If the key exists and its value is "Dark", the system is in dark
      # mode. The comparison `interface_style == "Dark"` evaluates to true
      # if the system is in dark mode, and false otherwise.
      interface_style = `defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null`.strip
      interface_style == "Dark" # Returns true (dark mode) or false (light mode or key missing)
    end
  end
end

# Example usage
# require_relative "macos_interface/dark_mode"
#
# if MacOSInterface::DarkMode.enabled?
#   puts "The system is in Dark Mode."
# else
#   puts "The system is in Light Mode."
# end

# Allow the script to run when executed
if __FILE__ == $PROGRAM_NAME

  puts
  puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
  # Call the listing method to start the test
  if MacOSInterface::DarkMode.enabled?
    puts "\033[0;33mThe system is in Dark Mode.\033[0m"
  else
    puts "\033[0;33mThe system is in Light Mode.\033[0m"
  end
  puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
end

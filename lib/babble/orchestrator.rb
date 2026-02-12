# typed: strict
# frozen_string_literal: true

require_relative "brew_upgrade"
require_relative "mas_upgrade"
require_relative "macos_update"
require_relative "waiter"

module Babble
  class Orchestrator
    class << self
      def run(config_file)
        puts "=" * 80
        puts "Babble: Automated System Upgrade"
        puts "=" * 80
        puts

        BrewUpgrade.run(config_file)

        puts "\n"
        puts "=" * 80
        Waiter.waiter("next_section", continuation_message: "Proceeding to Mac App Store upgrades...")
        puts

        MasUpgrade.run(config_file)

        puts "\n"
        puts "=" * 80
        Waiter.waiter("next_section", continuation_message: "Proceeding to macOS system updates...")
        puts

        MacOSUpdate.run

        puts "\n"
        puts "=" * 80
        puts "All upgrades complete!"
        puts "=" * 80
      end
    end
  end
end

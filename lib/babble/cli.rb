#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

require_relative "orchestrator"

module Babble
  class CLI
    class << self
      def run(args)
        config_file = find_config_file

        unless config_file && File.exist?(config_file)
          $stderr.puts "Error: Configuration file not found at #{config_file}"
          $stderr.puts "Please create config/apps.yml in the babble installation directory"
          exit 1
        end

        Orchestrator.run(config_file)
      end

      private

      def find_config_file
        script_dir = File.expand_path("..", __dir__)
        repo_root = File.expand_path("../..", script_dir)
        
        config_file = File.join(repo_root, "config", "apps.yml")
        
        return config_file if File.exist?(config_file)

        File.join(script_dir, "config", "apps.yml")
      end
    end
  end
end

if __FILE__ == $PROGRAM_NAME
  Babble::CLI.run(ARGV)
end

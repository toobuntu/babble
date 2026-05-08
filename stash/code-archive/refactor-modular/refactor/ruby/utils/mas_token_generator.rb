#!/usr/bin/env ruby

# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: strict
# frozen_string_literal: true

require "mkmf"
require "etc"
require "open3"

# MasTokenGenerator generates cask tokens for Mac App Store apps listed by `mas`.
class MasTokenGenerator
  HOMEBREW_PREFIX = ENV["HOMEBREW_PREFIX"] || `brew --prefix`.strip.freeze
  GENERATOR_PATH = File.join(
    HOMEBREW_PREFIX,
    "Library/Taps/homebrew/homebrew-cask/developer/bin/generate_cask_token",
  ).freeze

  def initialize
    validate_environment!
  end

  def generate_tokens
    threads_count = calculate_threads
    # $stderr.puts "\033[34m==> Info:\033[0m Using #{threads_count} threads for parallel execution with nice priority."

    app_names = fetch_mas_app_names
    tokens = parallel_generate_tokens(app_names, threads_count)

    puts tokens.sort
  end

  private

  def validate_environment!
    abort("Error: Generator tool not found at #{GENERATOR_PATH}") unless File.executable?(GENERATOR_PATH)
    abort("Error: 'mas' command not found") unless executable_exists?("mas")
  end

  def executable_exists?(cmd)
    ENV["PATH"].split(File::PATH_SEPARATOR).any? do |path|
      File.executable?(File.join(path, cmd))
    end
  end

  def calculate_threads
    [Etc.nprocessors - 1, 1].max
  end

  def fetch_mas_app_names
    output, status = Open3.capture2("mas list")
    abort("Error: failed to run 'mas list'") unless status.success?

    output.each_line.with_object([]) do |line, arr|
      if (match = line.match(/^\d+\s+(.+?)\s+\(.*\)$/))
        arr << match[1]
      end
    end
  end

  def parallel_generate_tokens(app_names, threads_count)
    queue = Queue.new
    app_names.each { |name| queue << name }

    tokens = Queue.new
    workers = Array.new(threads_count) do
      Thread.new do
        while (app_name = begin
          queue.pop(true)
        rescue
          nil
        end)
          generate_token_for(app_name) { |token| tokens << token if token }
        end
      end
    end

    workers.each(&:join)

    Array.new(tokens.size) { tokens.pop }
  end

  def generate_token_for(app_name)
    Open3.popen3("nice", "-n", "10", GENERATOR_PATH, app_name) do |_, stdout, _, wait_thr|
      stdout.each_line do |line|
        if line.start_with?("Proposed token:")
          token = line.split.last.strip
          yield token unless token.empty?
        end
      end
      wait_thr.value # ensure subprocess finishes properly
    end
  rescue => e
    warn "Warning: Failed to generate token for '#{app_name}': #{e.message}"
  end
end

MasTokenGenerator.new.generate_tokens if $PROGRAM_NAME == __FILE__

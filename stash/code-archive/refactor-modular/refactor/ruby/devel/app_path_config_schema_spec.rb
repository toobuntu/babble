# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: strict
# frozen_string_literal: true

require "rubocop"
require_relative "../../../lib/rubocop/cop/app_locator/config_schema"

RSpec.describe RuboCop::Cop::AppLocator::ConfigSchema do
  subject(:cop) { described_class.new }

  let(:valid_yaml) do
    <<~YAML
      stats:
        quit_ids:
          - eu.exelban.Stats
        reopen_ids:
          - eu.exelban.Stats
    YAML
  end

  let(:invalid_token_yaml) do
    <<~YAML
      Stats!:
        quit_ids:
          - eu.exelban.Stats
    YAML
  end

  let(:invalid_bundle_yaml) do
    <<~YAML
      stats:
        quit_ids:
          - invalid bundle id
    YAML
  end

  it "accepts valid config" do
    investigate(valid_yaml)
    expect(cop.offenses).to be_empty
  end

  it "registers offense for invalid token" do
    investigate(invalid_token_yaml)
    expect(cop.offenses.first.message).to include("Invalid Homebrew cask token")
  end

  it "registers offense for invalid bundle id" do
    investigate(invalid_bundle_yaml)
    expect(cop.offenses.first.message).to include("Invalid bundle ID")
  end

  define_method(:investigate) do |yaml|
    processed = RuboCop::ProcessedSource.new(yaml, RUBY_VERSION.to_f, "config.yml")
    commissioner = RuboCop::Cop::Commissioner.new([cop], [], raise_error: true)
    commissioner.investigate(processed)
  end
end

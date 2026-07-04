# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: true # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

require "cmd/shared_examples/args_parse"
require_relative "../../cmd/babble"

RSpec.describe Homebrew::Cmd::Babble do
  it_behaves_like "parseable arguments"

  describe "argument parsing" do
    it "accepts --no-update and --dry-run" do
      expect(described_class.new(["--no-update"]).args.no_update?).to be true
      expect(described_class.new(["--dry-run"]).args.dry_run?).to be true
    end

    it "rejects positional arguments" do
      expect { described_class.new(["extra"]).run }.to raise_error(Homebrew::CLI::MaxNamedArgumentsError)
    end
  end

  describe "#run" do
    before { allow(OS).to receive(:mac?).and_return(true) }

    it "prints the ⨀ banner with the version" do
      expect { described_class.new([]).run }
        .to output(/^==> ⨀ Babble #{Regexp.escape(Babble::VERSION)}$/o).to_stdout
    end

    it "prints the migration-in-progress notice" do
      expect { described_class.new([]).run }
        .to output(/^==> ⨀ Migration in progress; upgrade phases land in the C-blocks\.$/).to_stdout
    end

    it "raises UsageError when not on macOS" do
      allow(OS).to receive(:mac?).and_return(false)

      expect { described_class.new([]).run }
        .to raise_error(UsageError, /only supported on macOS/)
    end
  end
end

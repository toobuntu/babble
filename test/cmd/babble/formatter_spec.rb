# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: true # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

require "utils/github/actions"
require_relative "../../../cmd/babble/formatter"

RSpec.describe Babble::Formatter do
  # opoo/ofail emit GitHub Actions annotations to stdout when
  # GITHUB_ACTIONS is set; pin the plain-formatting path so expectations
  # hold both locally and on CI runners.
  before do
    allow(GitHub::Actions).to receive(:puts_annotation_if_env_set!).and_return(false)
  end

  describe "::PREFIX" do
    it "is the ⨀ glyph" do
      expect(described_class::PREFIX).to eq("⨀")
    end
  end

  describe ".oh1" do
    it "prefixes the message and delegates to Homebrew's oh1" do
      expect { described_class.oh1("Babble message") }
        .to output("==> ⨀ Babble message\n").to_stdout
    end
  end

  describe ".ohai" do
    it "prefixes the title and delegates to Homebrew's ohai" do
      expect { described_class.ohai("Quitting Stats...") }
        .to output("==> ⨀ Quitting Stats...\n").to_stdout
    end

    it "passes extra output lines through without the prefix" do
      expect { described_class.ohai("Title", "detail line") }
        .to output("==> ⨀ Title\ndetail line\n").to_stdout
    end
  end

  describe ".opoo" do
    it "prefixes the message and warns to stderr" do
      expect { described_class.opoo("Skipping iterm2 (running terminal)") }
        .to output("Warning: ⨀ Skipping iterm2 (running terminal)\n").to_stderr
    end
  end

  describe ".ofail" do
    it "prefixes the message, errors to stderr, and marks the run failed" do
      expect { described_class.ofail("Failed to launch Stats") }
        .to output("Error: ⨀ Failed to launch Stats\n").to_stderr

      expect(Homebrew).to have_failed
    end
  end
end

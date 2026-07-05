# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: true # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

require_relative "../../../cmd/babble/app_manager"

RSpec.describe Babble::AppManager do
  subject(:manager) { described_class.new(config: nil) }

  # Real `/usr/bin/lsappinfo list` output captured by the maintainer
  # (2026-07-04); never fabricated. 1019 lines, of which 134 carry
  # bundleID="..." — the rest must be excluded by the parser.
  let(:fixture) do
    File.read(File.expand_path("../../support/fixtures/babble/lsappinfo_list_sample.txt", __dir__))
  end

  define_method(:stub_capture) do |stdout:, status:|
    result = Babble::Sh::Result.new(stdout: stdout, stderr: "", status: status)
    allow(Babble::Sh).to receive(:capture)
      .with("/usr/bin/lsappinfo", "list").and_return(result)
  end

  describe "#running_bundle_ids" do
    it "parses at least one bundle id from the real fixture" do
      stub_capture(stdout: fixture, status: 0)
      ids = manager.running_bundle_ids
      expect(ids).to include("com.apple.loginwindow")
    end

    it "excludes lines without a bundleID assignment, de-dupes, and sorts" do
      stub_capture(stdout: fixture, status: 0)
      ids = manager.running_bundle_ids
      expect([ids.grep(/\A\s|"|=/), ids, ids.size <= fixture.lines.count { |l| l.include?('bundleID="') }])
        .to eq([[], ids.uniq.sort, true])
    end

    it "parses duplicate entries once" do
      stub_capture(stdout: %Q(  bundleID="com.example.App"\n  bundleID="com.example.App"\n), status: 0)
      expect(manager.running_bundle_ids).to eq(["com.example.App"])
    end

    it "returns only ids the refactor/modular validator accepts" do
      stub_capture(stdout: fixture, status: 0)
      expect(manager.running_bundle_ids.grep_v(Babble::AppManager::VALID_BUNDLE_ID)).to be_empty
    end

    it "warns about and excludes syntactically invalid bundle ids" do
      stub_capture(stdout: %Q(  bundleID="com.ok.App"\n  bundleID="bad id$(rm)"\n), status: 0)
      expect(Babble::Formatter).to receive(:opoo).with(/Ignoring invalid bundleID.*bad id/)

      expect(manager.running_bundle_ids).to eq(["com.ok.App"])
    end

    it "returns [] and warns via the ⨀ formatter on non-zero exit" do
      stub_capture(stdout: "", status: 1)
      expect(Babble::Formatter).to receive(:opoo).with(/lsappinfo list failed \(exit 1\)/)

      expect(manager.running_bundle_ids).to eq([])
    end
  end

  describe "#quit_app and #reopen_app" do
    it "raise NotImplementedError until the quit/reopen C-block" do
      expect { manager.quit_app("com.example.App") }.to raise_error(NotImplementedError)
      expect { manager.reopen_app("com.example.App") }.to raise_error(NotImplementedError)
    end
  end
end

# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: true # rubocop:disable Sorbet/StrictSigil
# frozen_string_literal: true

require_relative "../../../cmd/babble/sh"

RSpec.describe Babble::Sh do
  describe ".capture" do
    it "maps stdout, stderr, and exit status into a Result" do
      raw = instance_double(SystemCommand::Result,
                            exit_status: 0,
                            stdout:      "out\n",
                            stderr:      "err\n")
      expect(described_class).to receive(:system_command)
        .with("/usr/bin/true", args: ["--flag"], print_stderr: false, must_succeed: false)
        .and_return(raw)

      result = described_class.capture("/usr/bin/true", "--flag")
      expect([result.stdout, result.stderr, result.status, result.success?])
        .to eq(["out\n", "err\n", 0, true])
    end

    it "reports non-zero exits without raising" do
      raw = instance_double(SystemCommand::Result,
                            exit_status: 3,
                            stdout:      "",
                            stderr:      "boom")
      allow(described_class).to receive(:system_command).and_return(raw)

      result = described_class.capture("/usr/bin/false")
      expect([result.status, result.success?]).to eq([3, false])
    end

    it "reports a signal-killed command (nil exit status) as status 1" do
      raw = instance_double(SystemCommand::Result,
                            exit_status: nil,
                            stdout:      "",
                            stderr:      "")
      allow(described_class).to receive(:system_command).and_return(raw)

      expect(described_class.capture("/usr/bin/false").status).to eq(1)
    end
  end
end

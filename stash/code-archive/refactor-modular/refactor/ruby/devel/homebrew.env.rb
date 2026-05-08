# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# typed: strict
# frozen_string_literal: true

puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
# Set the HOMEBREW_INSTALL_BADGE with ANSI escape codes in Ruby
ENV["HOMEBREW_INSTALL_BADGE"] = "\e[32m\u{2A00}\e[0m"
system("brew", "upgrade", "--greedy-latest")
puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")

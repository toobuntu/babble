# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

# lib/config/config_loader.rb
# frozen_string_literal: true
#
# This class provides the top-level entrypoint for loading the merged
# configuration. Both brew_upgrade.rb and mas_upgrade.rb can require this file
# to obtain the processed configuration.
#
require_relative "loader"

module ConfigLoader
  class << self
    def load_config
      Config::Loader.run
    end

    private

    # No additional private methods are required.
  end
end

# copilot

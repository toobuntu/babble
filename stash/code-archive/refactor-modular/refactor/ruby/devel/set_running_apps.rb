# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

def self.set_running_apps
  require "open3"

  # Equivalent to `/usr/bin/lsappinfo list | /usr/bin/sed -nE 's/.*bundleID="([^"]+).*"/\1/p' | sort | uniq`
  stdout, status = Open3.capture2("/usr/bin/lsappinfo list")

  if status.success?
    bundle_ids = stdout.scan(/bundleID="([^"]+)"/).flatten
    bundle_ids.sort.uniq.each { |id| puts id } # Print out the bundle IDs
  else
    $stderr.puts "Error getting running apps."
    []
  end
end

set_running_apps

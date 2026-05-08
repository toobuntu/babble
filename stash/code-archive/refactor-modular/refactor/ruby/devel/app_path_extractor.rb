#!/usr/bin/env ruby

# SPDX-FileCopyrightText: Copyright 2026 Todd Schulman
#
# SPDX-License-Identifier: GPL-3.0-or-later

require 'json'
require 'open3'
require 'net/http'
require 'uri'

module AppPathLocator
  class Extractors
def run_cmd(cmd)
  stdout, stderr, status = Open3.capture3(cmd)
  status.success? ? stdout.strip : nil
end

# Canonical Tier 1 extractor: use cask metadata + formula API
def cask_metadata_path(cask)
  # Locate the caskroom config.json
  caskroom = `brew --caskroom`.strip
  return nil if caskroom.empty?

  config_path = File.join(caskroom, cask, ".metadata", "config.json")
  return nil unless File.exist?(config_path)

  # Parse JSON directly in Ruby
  # Equivalent to:
  # appdir = run_cmd(%Q{jq -r '.explicit.appdir // .env.appdir // .default.appdir' "#{config_path}"})
  config = JSON.parse(File.read(config_path))
  appdir = config.dig("explicit", "appdir") ||
           config.dig("env", "appdir") ||
           config.dig("default", "appdir")
  return nil unless appdir

  # Fetch artifacts from the formula API
  url = URI("https://formulae.brew.sh/api/cask/#{cask}.json")
  response = Net::HTTP.get_response(url)
  return nil unless response.is_a?(Net::HTTPSuccess)

  data = JSON.parse(response.body)
  artifacts = data["artifacts"].flat_map do |artifact|
    artifact["app"] if artifact.is_a?(Hash)
  end.compact

  # Construct full paths and return those that exist
  artifacts.map { |app| File.join(appdir, app) }.select { |path| Dir.exist?(path) }
end

# 1. Try caskroom symlink
def caskroom_path(cask)
  caskroom = run_cmd("brew --caskroom")
  return nil unless caskroom && !caskroom.empty?
  path = File.join(caskroom, cask)
  Dir.exist?(path) ? path : nil
end


# 2. Query LaunchServices via lsregister
def lsregister_path(bundle_id)
  lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/" \
               "LaunchServices.framework/Versions/A/Support/lsregister"
  return nil unless File.executable?(lsregister)

  stdout, _stderr, status = Open3.capture3("#{lsregister} -dump")
  return nil unless status.success?

  path = nil
  stdout.each_line do |line|
    if line =~ /^path:\s+(.+?)(?: \(0x[0-9A-Fa-f]+\))?$/
      path = $1
    elsif line =~ /^identifier:\s+(.+?)(?: \(0x[0-9A-Fa-f]+\))?$/
      id = $1
      if id == bundle_id && path && path =~ /\.app$/ && path !~ /\/Contents\//
        return path
      end
      path = nil
    end
  end
  nil
end

# 3. Spotlight search
def mdfind_path(bundle_id)
  out = run_cmd(%Q{mdfind 'kMDItemCFBundleIdentifier == "#{bundle_id}"'})
  out&.lines&.map(&:strip)&.first
end

# 4. AppleScript via osascript
def osascript_path(bundle_id)
  run_cmd(%Q{osascript -e 'POSIX path of (path to application id "#{bundle_id}")'})&.strip
end

# 5. Fallback: look in /Applications
def applications_path(app_name)
  path = File.join("/Applications", app_name)
  File.directory?(path) ? path : nil
end

# Ordered extractor
def find_app_path(cask: nil, bundle_id: nil, app_name: nil)
  cask_metadata_path(cask) ||          # Tier 1 (canonical): cask metadata + formula API (works only for DMG casks)
    caskroom_path(cask) ||             # Old Tier 1: Caskroom symlink resolution (works only for DMG casks)
    lsregister_path(bundle_id) ||      # Tier 2: LaunchServices database (also works for PKG casks)
    mdfind_path(bundle_id) ||          # Tier 3: Spotlight metadata
    osascript_path(bundle_id) ||       # Tier 4: AppleScript
    applications_path(app_name)        # Tier 5: filesystem fallback
end

  end
end
# Example usage
puts find_app_path(
  cask: "adobe-acrobat-reader",
  bundle_id: "com.adobe.Reader",
  app_name: "Adobe Acrobat Reader.app"
)


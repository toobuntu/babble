require "json"
require "yaml"
require "open3"

# Load configuration file
config_file = ARGV[0] || "path/to/config.yml"

begin
  config = YAML.load_file(config_file)
rescue Errno::ENOENT
  abort "Error: Configuration file not found at #{config_file}"
rescue Psych::SyntaxError => e
  abort "Error: Syntax error in configuration file - #{e.message}"
end

homebrew_apps = config.dig("apps", "homebrew") || []

# Remove specific xattrs from the app bundle
def bypass_gatekeeper(cask)
  caskroom_path, _stderr, status = Open3.capture3("brew --caskroom")
  unless status.success?
    warn "Error: Failed to retrieve Caskroom path"
    return
  end

  app_path = File.join(caskroom_path.strip, cask)

  if Dir.exist?(app_path)
    %w[com.apple.quarantine com.apple.provenance].each do |xattr|
      warn "Removing xattr #{xattr} for: #{app_path}"
      system("/usr/bin/xattr -dr #{xattr} '#{app_path}'") || warn("Warning: Failed to remove #{xattr} for #{app_path}")
    end
  else
    warn "Caskroom path not found for #{cask}. Skipping Gatekeeper bypass."
  end
end

# Upgrade and optionally handle quarantine removal
def upgrade_cask(cask, bypass_gatekeeper_flag)
  warn "Upgrading cask: #{cask}"
  if system("brew upgrade --cask #{cask}")
    bypass_gatekeeper(cask) if bypass_gatekeeper_flag
  else
    warn "Error: Upgrade failed for #{cask}. Skipping Gatekeeper bypass."
  end
end

# Process Homebrew apps
homebrew_apps.each do |app|
  token = app["token"]
  bypass_gatekeeper_flag = app["bypass_gatekeeper"]

  # Logging
  if bypass_gatekeeper_flag
    warn "Bypassing Gatekeeper for: #{token}"
  else
    warn "No Gatekeeper bypass required for: #{token}"
  end

  upgrade_cask(token, bypass_gatekeeper_flag)
end

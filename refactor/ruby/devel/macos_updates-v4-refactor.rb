# typed: strict
# frozen_string_literal: true

require "open3"
require "pty"
require "logger"
require "fileutils"
require_relative "../ui/waiter"

module MacOSUpdates
  # MacOSUpdateManager handles the macOS update workflow (listing and installation).
  #
  # Design Decision:
  # This class is designed as an instance-based object to encapsulate state
  # (e.g., @updates_available and logger) locally, which improves testability
  # and maintainability by avoiding global (class-level) state.
  class MacOSUpdateManager
    SOFTWAREUPDATE_PATH = "/usr/sbin/softwareupdate"
    SUDO_PATH           = "/usr/bin/sudo"

    def initialize
      @updates_available = nil
      @restart_required = false
      setup_logger
      log_info("Initialized MacOSUpdateManager")
    end

    # Public: Orchestrates the update workflow.
    # Calls list_updates and, if updates are available, proceeds with install_updates.
    def run
      list_updates
      install_updates if @updates_available
    end

    # Public: Lists available updates and sets the @updates_available flag accordingly.
    def list_updates
      log_info("Starting update listing process")
      puts "\nListing available macOS updates. This may take some time."
      puts "Would run `softwareupdate --list --include-config-data`"
      Waiter.waiter("run_command")
      puts "Please wait..."

      # NOTE: The --include-config-data option is undocumented. It includes security data updates such as those to MRT, XProtect and XProtect Remediator.
      # Ref https://eclecticlight.co/2023/09/06/taking-manual-control-of-macos-updates-with-softwareupdate/.
      # The --restart option might no longer be required and softwareupdate will do a restart if it is required without it.
      # sudo might no longer be required.
      stdout, stderr, status = Open3.capture3(SOFTWAREUPDATE_PATH, "--list", "--include-config-data")

      unless status.success?
        log_error("Error during update listing: #{stderr.strip}")
        $stderr.puts "\nErrors occurred while checking for updates:"
        $stderr.puts(stderr) unless stderr.empty?
        @updates_available = false
        return
      end

      if stderr.include?("No new software available.")
        log_info("No new updates available; exiting update process")
        puts "No updates available."
        @updates_available = false
      else
        puts stdout unless stdout.empty?
        $stderr.puts(stderr) unless stderr.empty?
        log_info("Updates found; proceeding to installation")
        @updates_available = true
        @restart_required = stdout.include?("Action: restart")
      end
    end

    # Public: Installs updates if @updates_available is true.
    def install_updates
      unless @updates_available
        puts "No updates available, skipping installation."
        return
      end

      log_info("Preparing to install updates")
      puts "\nInstalling all available updates to macOS..."
      if @restart_required
        puts "A system restart may occur if required to complete installation."
      end
      puts "Would run `softwareupdate --install --all --include-config-data`"
      # Passing --restart requires root privilege.
      # puts "Would run `sudo softwareupdate --install --all --include-config-data --restart --agree-to-license`"
      Waiter.waiter("run_command")

      captured_stdout = run_install_command
      process_installation_output(captured_stdout)
    end

    private

    # Sets up a logger that writes to ~/Library/Logs/MacOSUpdateManager.log.
    def setup_logger
      log_dir = File.join(Dir.home, "Library", "Logs")
      FileUtils.mkdir_p(log_dir)
      log_file = File.join(log_dir, "MacOSUpdateManager.log")
      @logger = Logger.new(log_file, "daily")
      @logger.level = Logger::INFO
    end

    # Executes the installation command via PTY and captures its output.
    def run_install_command
      command = "#{SOFTWAREUPDATE_PATH} --install --all --include-config-data"
      # command = "#{SUDO_PATH} #{SOFTWAREUPDATE_PATH} --install --all --include-config-data --restart"
      captured_stdout = String.new
      begin
        PTY.spawn(command) do |stdout, _stdin, _pid|
          stdout.each do |line|
            puts line
            captured_stdout << line
            @logger.info(line.strip)
          end
        rescue Errno::EIO
          log_info("PTY output reading terminated (possibly due to a restart).")
        end
      rescue PTY::ChildExited => e
        log_info("Child process exited: #{e.message}")
      rescue => e
        log_error("Unexpected error during installation: #{e.message}")
        $stderr.puts "\nAn unexpected error occurred: #{e.message}"
        exit 1
      end
      captured_stdout
    end

    # Checks captured output for restart action and notifies the user accordingly.
    def process_installation_output(captured_stdout)
      if captured_stdout.include?("Action: restart")
        puts "\nUpdates ready. A system restart is required to complete installation..."
        log_info("Detected restart action in installation output.")
      else
        puts "\nUpdates installed successfully."
        log_info("Updates installed successfully without requiring a restart.")
      end
    end

    # Logs an informational message.
    def log_info(message)
      @logger.info(message)
    end

    # Logs an error message.
    def log_error(message)
      @logger.error(message)
    end
  end
end

# If the script is executed directly, instantiate and run the update manager.
if __FILE__ == $PROGRAM_NAME
  puts
  puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
  updater = MacOSUpdates::MacOSUpdateManager.new
  updater.run
  puts Time.now.strftime("%a %b %e %H:%M:%S %Z %Y")
end

# copilot

# typed: strict
# frozen_string_literal: true

require "open3"
require "timeout"

module MacUtils
  # BundleLauncher class
  # Public API: BundleLauncher.launch(bundle_id, timeout: 10)
  # Launches an app by bundle ID, waiting until it is registered and ready.
  # Raises RuntimeError if launch fails or times out.
  class BundleLauncher
    # OPEN = "/usr/bin/open"
    LSREGISTER = File.join(
      "/System/Library/Frameworks/CoreServices.framework",
      "Versions/A/Frameworks/LaunchServices.framework",
      "Versions/A/Support",
      "lsregister"
    )

    # sig { params(bundle_id: String, timeout: Integer).returns(T::Boolean) }
    def self.launch(bundle_id, timeout: 10)
      bundle_id = sanitized_bundle_id(bundle_id)
      run_open(bundle_id)
      wait_until_reopened(bundle_id, timeout)
      true
    rescue OpenLaunchError => e
      # Resolve path for targeted re-registration
      path = app_path_via_mdfind(bundle_id) || app_path_via_lsregister_dump(bundle_id)
      if path && File.directory?(path)
        force_ls_registration(path)
        run_open(bundle_id)
        wait_until_reopened(bundle_id, timeout)
      end
    end

    class << self
      private

      def sanitized_bundle_id(raw)
        return unless raw

        id = raw.to_s.gsub(/[[:cntrl:]]/, "").strip
        raise "invalid bundle id" unless /\A[a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+\z/i.match?(id)

        id
      end

      # sig { params(bundle_id: String, tries: Integer).returns(T::Boolean) }
      def run_open(bundle_id, tries: 3)
        # def run_open(bundle_id)
        # original
        # _, stderr, status = Open3.capture3("/usr/bin/open", "-g", "-b", bundle_id)
        # raise "Failed to launch #{bundle_id}: #{stderr}" unless status.success?

        attempts = 0
        begin
          attempts += 1
          stdout, stderr, status = Open3.capture3("/usr/bin/open", "-g", "-b", bundle_id)
          $stderr.puts "/usr/bin/open exitstatus: #{status.exitstatus} success?: #{status.success?}"
          $stderr.puts "/usr/bin/open stdout: #{stdout.inspect}"
          $stderr.puts "/usr/bin/open stderr: #{stderr.inspect}"
          raise OpenLaunchError.new(stderr, stdout, status) unless status.success?

          true
        rescue OpenLaunchError => e
          if attempts < tries
            # if attempts < tries && retryable_ls_copy_error?(e)
            sleep 0.15 * attempts
            retry
          end

          # Final failure: structured logging, then fallback attempt in GUI session.
          $stderr.puts "Final failure launching #{bundle_id}: #{e.message}"
          $stderr.puts "Structured: #{e.to_h.inspect}"

          attempt_launch_in_gui_session(bundle_id)

          raise
        end
      end

      # sig { params(error: OpenLaunchError).returns(T::Boolean) }
      # def retryable_ls_copy_error?(error)
      #   error.stderr.to_s.include?("LSCopyApplicationURLsForBundleIdentifier")
      # end

      def attempt_launch_in_gui_session(bundle_id)
        $stderr.puts "Attempting launchctl in the GUI session..."
        uid = Process.uid.to_s
        out, err, st = Open3.capture3("launchctl", "asuser", uid, "/usr/bin/open", "-g", "-b", bundle_id)
        $stderr.puts "launchctl asuser exit: #{st.exitstatus} stdout: #{out.inspect} stderr: #{err.inspect}"
      end

      # sig { params(bundle_id: String, timeout: Integer).void }
      def wait_until_reopened(bundle_id, timeout)
        Timeout.timeout(timeout) do
          sleep 0.5 until reopened?(bundle_id)
        end
      rescue Timeout::Error
        raise "Timeout waiting for #{bundle_id} to reopen"
      end

      # sig { params(bundle_id: String).returns(T::Boolean) }
      def reopened?(bundle_id)
        stdout, _stderr, status = Open3.capture3(
          "/usr/bin/lsappinfo", "info", "-only", "isregistered,isready", "-app", bundle_id
        )
        status.success? &&
          stdout.include?('"LSApplicationHasRegistered"=true') &&
          stdout.include?('"LSApplicationHasSignalledItIsReady"=true')
      end

      # sig { params(bundle_id: String).returns(T.nilable(String)) }
      def app_path_via_mdfind(bundle_id)
        stdout, _stderr, status = Open3.capture3("mdfind", "kMDItemCFBundleIdentifier == '#{bundle_id}'")
        return unless status.success?

        stdout.lines.map(&:chomp).find { |path| path.end_with?(".app") }
      end

      # sig {
      #   params(
      #     bundle_id: String,
      #     debug:     T::Boolean,
      #   ).returns(T.nilable(String))
      # }
      def app_path_via_lsregister_dump(bundle_id, debug: false)
        out, _err, st = Open3.capture3("#{LSREGISTER} -dump")
        return unless st.success?

        current_path = nil
        candidates = []

        out.each_line do |line|
          if line.strip.empty?
            current_path = nil
            next
          end

          if (m = line.match(/^\s*path:\s*(.+)$/))
            raw = m[1].strip
            next if raw.include?("/Contents/Helpers/")

            # Strip trailing LS registration ID if present
            current_path = raw.sub(/\s*\(0x[0-9a-fA-F]+\)\s*$/, "")
            # $stderr.puts " [lsreg] path: #{current_path}" if debug
            next
          end

          next unless (m = line.match(/^\s*identifier:\s*(.+)/i))

          id = m[1].strip
          next if id.downcase != bundle_id.downcase
          next unless current_path

          $stderr.puts " [lsreg] path: #{current_path}" if debug
          $stderr.puts " [lsreg] identifier matched: #{id}" if debug
          candidates << current_path
        end

        return if candidates.empty?

        # Normalize each candidate to its top-level .app and validate
        normalized = candidates.filter_map { |p| top_level_app(p, bundle_id, debug: debug) }
        normalized.min_by(&:length)
      end

      # Walk upward until the nearest .app bundle
      # sig {
      #   params(
      #     path:               String,
      #     expected_bundle_id: String,
      #     debug:              T::Boolean,
      #   ).returns(T.nilable(String))
      # }
      def top_level_app(path, expected_bundle_id, debug: false)
        p = Pathname.new(path)
        $stderr.puts " [walker] starting at: #{p}" if debug
        while p.to_s != "/"
          if p.to_s.end_with?(".app")
            parent = p.parent
            if parent.to_s.end_with?(".app")
              p = parent
              next
            end
            plist = p.join("Contents/Info.plist").to_s
            if File.file?(plist)
              out, _err, st = Open3.capture3(
                "/usr/libexec/PlistBuddy",
                "-c", "Print :CFBundleIdentifier",
                plist
              )
              if st.success? && out.strip.casecmp?(expected_bundle_id)
                $stderr.puts " [walker] resolved top-level app: #{p}" if debug
                return p.to_s
              end
            end
          end

          p = p.parent
          $stderr.puts " [walker] stepping to: #{p}" if debug
        end

        nil
      end

      # Targeted LaunchServices refresh
      # sig { params(app_path: String).void }
      def force_ls_registration(app_path)
        Open3.capture3(LSREGISTER, "-f", app_path)
      end
    end
  end

  # Raised when an attempt to launch an app via /usr/bin/open fails.
  # Carries stdout, stderr and Process::Status for diagnostics.
  class OpenLaunchError < RuntimeError
    attr_reader :stdout, :stderr, :status

    def initialize(stderr = nil, stdout = nil, status = nil, message = nil)
      @stdout = stdout
      @stderr = stderr
      @status = status
      msg = message || compose_message
      super(msg)
    end

    def exitstatus
      status.respond_to?(:exitstatus) ? status.exitstatus : nil
    end

    def success?
      status.respond_to?(:success?) ? status.success? : false
    end

    def to_h
      {
        message:    message,
        stdout:     stdout,
        stderr:     stderr,
        exitstatus: exitstatus,
      }
    end

    private

    def compose_message
      pieces = []
      pieces << "open failed"
      pieces << "exit: #{exitstatus}" if exitstatus
      pieces << "stderr: #{stderr.strip}" if stderr && !stderr.strip.empty?
      pieces << "stdout: #{stdout.strip}" if stdout && !stdout.strip.empty?
      pieces.join(" | ")
    end
  end
end

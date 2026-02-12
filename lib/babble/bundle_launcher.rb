# typed: strict
# frozen_string_literal: true

require "open3"
require "timeout"

module Babble
  class BundleLauncher
    LSREGISTER = File.join(
      "/System/Library/Frameworks/CoreServices.framework",
      "Versions/A/Frameworks/LaunchServices.framework",
      "Versions/A/Support",
      "lsregister"
    )

    class OpenLaunchError < StandardError
      attr_reader :stderr, :stdout, :status

      def initialize(stderr, stdout, status)
        @stderr = stderr
        @stdout = stdout
        @status = status
        super("Launch failed: #{stderr}")
      end

      def to_h
        { stderr: @stderr, stdout: @stdout, exitstatus: @status.exitstatus }
      end
    end

    class << self
      def launch(bundle_id, timeout: 10)
        bundle_id = sanitized_bundle_id(bundle_id)
        run_open(bundle_id)
        wait_until_reopened(bundle_id, timeout)
        true
      rescue OpenLaunchError => e
        path = app_path_via_mdfind(bundle_id) || app_path_via_lsregister_dump(bundle_id)
        if path && File.directory?(path)
          force_ls_registration(path)
          run_open(bundle_id)
          wait_until_reopened(bundle_id, timeout)
        else
          raise
        end
      end

      private

      def sanitized_bundle_id(raw)
        raise "invalid bundle id" unless raw

        id = raw.to_s.gsub(/[[:cntrl:]]/, "").strip
        raise "invalid bundle id" unless /\A[a-z0-9_.-]+(?:\.[a-z0-9_.-]+)+\z/i.match?(id)

        id
      end

      def run_open(bundle_id, tries: 3)
        attempts = 0
        begin
          attempts += 1
          stdout, stderr, status = Open3.capture3("/usr/bin/open", "-g", "-b", bundle_id)
          raise OpenLaunchError.new(stderr, stdout, status) unless status.success?

          true
        rescue OpenLaunchError => e
          if attempts < tries
            sleep 0.15 * attempts
            retry
          end

          $stderr.puts "Final failure launching #{bundle_id}: #{e.message}"
          attempt_launch_in_gui_session(bundle_id)
          raise
        end
      end

      def attempt_launch_in_gui_session(bundle_id)
        uid = Process.uid
        stdout, stderr, status = Open3.capture3(
          "launchctl", "asuser", uid.to_s, "/usr/bin/open", "-g", "-b", bundle_id
        )

        if status.success?
          $stderr.puts "Successfully launched #{bundle_id} via launchctl asuser"
        else
          $stderr.puts "launchctl asuser also failed: #{stderr}"
        end
      end

      def wait_until_reopened(bundle_id, timeout)
        Timeout.timeout(timeout) do
          loop do
            break if app_registered?(bundle_id)

            sleep 0.2
          end
        end
      rescue Timeout::Error
        raise "Timeout waiting for #{bundle_id} to register"
      end

      def app_registered?(bundle_id)
        stdout, _, status = Open3.capture3(
          LSREGISTER, "-dump",
          err: File::NULL
        )

        return false unless status.success?

        stdout.include?(bundle_id)
      end

      def app_path_via_mdfind(bundle_id)
        stdout, _, status = Open3.capture3(
          "mdfind", "kMDItemCFBundleIdentifier == '#{bundle_id}'"
        )

        return nil unless status.success?

        paths = stdout.split("\n").select { |p| p.end_with?(".app") }
        paths.first
      end

      def app_path_via_lsregister_dump(bundle_id)
        stdout, _, status = Open3.capture3(
          LSREGISTER, "-dump",
          err: File::NULL
        )

        return nil unless status.success?

        in_bundle_block = false
        current_path = nil

        stdout.each_line do |line|
          line.strip!

          if line.start_with?("bundle id:")
            in_bundle_block = (line.include?(bundle_id))
          elsif in_bundle_block && line.start_with?("path:")
            current_path = line.sub(/^path:\s*/, "")
            return current_path if current_path.end_with?(".app")
          elsif line.empty?
            in_bundle_block = false
            current_path = nil
          end
        end

        nil
      end

      def force_ls_registration(path)
        $stderr.puts "Forcing LSRegister update for #{path}"
        stdout, stderr, status = Open3.capture3(
          LSREGISTER, "-f", path
        )

        unless status.success?
          $stderr.puts "LSRegister failed: #{stderr}"
        end
      end
    end
  end
end

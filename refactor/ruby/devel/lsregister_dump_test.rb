# typed: false
# frozen_string_literal: true

require "open3"
require "pathname"

# LsregisterPathTest prints the app path for bundle ID
class LSRegisterPathTest
  class << self
    LSREGISTER = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/" \
                 "LaunchServices.framework/Versions/A/Support/lsregister"

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

        if (m = line.match(/^\s*identifier:\s*(.+)/i))
          id = m[1].strip
          next if id.downcase != bundle_id.downcase
          next unless current_path

          $stderr.puts " [lsreg] path: #{current_path}" if debug
          $stderr.puts " [lsreg] identifier matched: #{id}" if debug
          candidates << current_path
        end
      end

      return if candidates.empty?

      # Normalize each candidate to its top-level .app and validate
      normalized = candidates.map { |p| top_level_app(p, bundle_id, debug: debug) }.compact
      normalized.min_by(&:length)
    end

    private

    # Walk upward until the nearest .app bundle
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
  end
end

if __FILE__ == $PROGRAM_NAME
  BUNDLE_ID = "com.mowglii.ItsycalApp"

  args = ARGV.dup
  debug = false

  if args.include?("--debug")
    debug = true
    args.delete("--debug")
  end

  bundle_id = args[0] || BUNDLE_ID

  if bundle_id.empty?
    warn "Usage: ruby test_lsregister_path.rb [--debug] <bundle-id>"
    exit 1
  end

  $stderr.puts "[debug] bundle_id=#{bundle_id}" if debug

  path = LSRegisterPathTest.app_path_via_lsregister_dump(bundle_id, debug: debug)
  if path
    puts "Resolved path: #{path}"
  else
    puts "No path found for bundle ID: #{bundle_id}"
  end
end

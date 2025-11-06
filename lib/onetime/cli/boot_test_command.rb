# lib/onetime/cli/boot_test_command.rb
#
# CLI command for testing application boot and initialization
#
# This command boots the application and initializes all apps via the central
# registry, then exits with a success/failure status. Useful for validating
# that all Ruby code paths are correct after refactoring.
#
# Usage:
#   ots boot-test
#
# Exit codes:
#   0 - Boot successful
#   1 - Boot failed
#

module Onetime
  class BootTestCommand < Onetime::CLI::DelayBoot
    def boot_test
      puts "Testing application boot..."
      puts ""

      begin
        # Boot the application (same as config.ru)
        Onetime.boot! :app

        # Prepare the application registry (discovers and loads all apps)
        Onetime::Application::Registry.prepare_application_registry

        # Check if application is ready
        unless Onetime.ready?
          $stderr.puts "❌ Application boot failed: not ready"
          exit 1
        end

        # Generate the URL map to ensure all apps can be instantiated
        url_map = Onetime::Application::Registry.generate_rack_url_map

        # Success!
        puts "✅ Boot test successful!"
        puts ""
        puts "Loaded applications:"
        Onetime::Application::Registry.mount_mappings.each do |path, app_class|
          puts "  #{path.ljust(20)} → #{app_class}"
        end
        puts ""

        exit 0

      rescue => ex
        $stderr.puts "❌ Boot test failed: #{ex.class}: #{ex.message}"
        if global.verbose || global.debug
          $stderr.puts ""
          $stderr.puts "Backtrace:"
          $stderr.puts ex.backtrace.join("\n")
        else
          $stderr.puts ""
          $stderr.puts "Use --verbose for full backtrace"
        end
        exit 1
      end
    end
  end
end

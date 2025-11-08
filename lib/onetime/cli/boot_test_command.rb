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
    include Onetime::LoggerMethods

    def boot_test
      puts "Testing application boot..."
      puts ""

      begin
        # Boot the application (same as config.ru)
        Onetime.boot! :app
        sleep 0.1 # give the semantic loggers a moment to drain

        # Check readiness after boot
        unless Onetime.ready?
          $stderr.puts "Boot test failed: Application boot incomplete"
          $stderr.puts "The application failed to initialize properly."
          exit 1
        end

        # Prepare the application registry (discovers and loads all apps)
        Onetime::Application::Registry.prepare_application_registry
        sleep 0.1 # let loggers drain

        # Check readiness after registry preparation
        unless Onetime.ready?
          $stderr.puts "Boot test failed: Application registry preparation failed"
          $stderr.puts "One or more applications failed to load. Check error output above for details."
          $stderr.puts "Common causes: Namespace mismatches, missing files, or syntax errors"
          exit 1
        end

        # Generate the URL map to ensure all apps can be instantiated
        url_map = Onetime::Application::Registry.generate_rack_url_map

        # Perform health check on all applications
        health_status = Onetime::Application::Registry.health_check

        unless health_status[:healthy]
          $stderr.puts "Boot test failed: One or more applications unhealthy"

          health_status[:applications].each do |app_name, health|
            next if health[:healthy]

            $stderr.puts "Unhealthy application",
              application: app_name,
              router_present: health[:router_present],
              rack_app_present: health[:rack_app_present]
          end
          exit 1
        end

        sleep 0.1 # log drain

        # Success!
        $stderr.puts "Boot test successful!"
        $stderr.puts "Loaded applications:"
        Onetime::Application::Registry.mount_mappings.each do |path, app_class|
          $stderr.puts "  #{path.ljust(20)} → #{app_class}"
        end

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

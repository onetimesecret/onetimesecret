# lib/onetime/cli/boot_test_command.rb
#
# frozen_string_literal: true

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
  module CLI
    class BootTestCommand < DelayBootCommand
      include Onetime::LoggerMethods

      desc 'Test application boot and registry initialization'

      def call(**)
        puts 'Testing application boot...'
        puts ''

        begin
          # Boot the application (same as config.ru)
          Onetime.boot! :app
          sleep 0.1 # give the semantic loggers a moment to drain

          # Check readiness after boot
          unless Onetime.ready?
            warn 'Boot test failed: Application boot incomplete'
            warn 'The application failed to initialize properly.'
            exit 1
          end

          # Prepare the application registry (discovers and loads all apps)
          Onetime::Application::Registry.prepare_application_registry
          sleep 0.1 # let loggers drain

          # Check readiness after registry preparation
          unless Onetime.ready?
            warn 'Boot test failed: Application registry preparation failed'
            warn 'One or more applications failed to load. Check error output above for details.'
            warn 'Common causes: Namespace mismatches, missing files, or syntax errors'
            exit 1
          end

          # Generate the URL map to ensure all apps can be instantiated
          Onetime::Application::Registry.generate_rack_url_map

          # Perform health check on all applications
          health_status = Onetime::Application::Registry.health_check

          unless health_status[:healthy]
            warn 'Boot test failed: One or more applications unhealthy'

            health_status[:applications].each do |app_name, health|
              next if health[:healthy]

              warn 'Unhealthy application',
                application: app_name,
                router_present: health[:router_present],
                rack_app_present: health[:rack_app_present]
            end
            exit 1
          end

          sleep 0.1 # log drain

          # Success!
          warn 'Boot test successful!'
          warn 'Loaded applications:'
          Onetime::Application::Registry.mount_mappings.each do |path, app_class|
            warn "  #{path.ljust(20)} → #{app_class}"
          end

          exit 0
        rescue StandardError => ex
          warn "❌ Boot test failed: #{ex.class}: #{ex.message}"
          if verbose? || debug?
            warn ''
            warn 'Backtrace:'
            warn ex.backtrace.join("\n")
          else
            warn ''
            warn 'Use --verbose for full backtrace'
          end
          exit 1
        end
      end
    end

    register 'boot-test', BootTestCommand
  end
end

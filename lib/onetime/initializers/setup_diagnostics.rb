# lib/onetime/initializers/setup_diagnostics.rb
#
# frozen_string_literal: true

module Onetime
  module Initializers
    # SetupDiagnostics initializer
    #
    # Configures Sentry error tracking and performance monitoring if diagnostics
    # are enabled. Sets up breadcrumbs logging, sampling rates, and environment
    # information for error context.
    #
    # Runtime state set:
    # - Onetime::Runtime.infrastructure.d9s_enabled
    #
    class SetupDiagnostics < Onetime::Boot::Initializer
      def execute(_context)
        d9s_enabled = conf['diagnostics']['enabled'] || false

        unless d9s_enabled
          Onetime::Runtime.update_infrastructure(d9s_enabled: false)
          return
        end

        backend   = conf['diagnostics']['sentry']['backend']
        dsn       = backend.fetch('dsn', nil)
        site_host = conf.dig('site', 'host')

        OT.ld "[init] Setting up Sentry #{backend}..."

        # Log more details about the Sentry configuration for debugging
        OT.ld "[init] Sentry: DSN present: #{!dsn.nil?}"
        OT.ld "[init] Sentry: Site host: #{site_host.inspect}"
        OT.ld "[init] Sentry: OT.env: #{OT.env.inspect}"

        # Early validation to prevent nil errors during initialization
        if dsn.nil?
          OT.ld '[init] Sentry: Cannot initialize Sentry with nil DSN'
          d9s_enabled = false
        elsif site_host.nil?
          OT.le '[init] Sentry: Cannot initialize Sentry with nil site_host'
          OT.ld 'Falling back to default environment name'
          site_host = 'unknown-host'
        end

        # Only proceed if we have valid configuration
        unless d9s_enabled
          Onetime::Runtime.update_infrastructure(d9s_enabled: false)
          return
        end

        # Safely log first part of DSN for debugging
        dsn_preview = dsn ? "#{dsn[0..10]}..." : 'nil'
        OT.boot_logger.info "[init] Sentry: Initializing with DSN: #{dsn_preview}"

        # Only require Sentry if we have a DSN. We call explicitly
        # via Kernel to aid in testing.
        Kernel.require 'sentry-ruby'
        Kernel.require 'stackprof'

        Sentry.init do |config|
          config.dsn         = dsn
          config.environment = "#{site_host} (#{OT.env})"
          config.release     = OT::VERSION.inspect

          # Configure breadcrumbs logger for detailed error tracking.
          # Uses sentry_logger to capture progression of events leading
          # to errors, providing context for debugging.
          config.breadcrumbs_logger = [:sentry_logger]

          # Set traces_sample_rate to capture 10% of
          # transactions for performance monitoring.
          config.traces_sample_rate = 0.1

          # Set profiles_sample_rate to profile 10%
          # of sampled transactions.
          config.profiles_sample_rate = 0.1

          # Add a before_send to filter out problematic events that might cause errors
          config.before_send = ->(event, _hint) do
            # Return nil if the event would cause errors in processing
            if event.nil? || event.request.nil? || event.request.headers.nil?
              OT.ld '[init] Sentry: Filtering out event with nil components'
              return nil
            end

            # Return the event if it passes validation
            event
          end
        end

        OT.ld "[init] Sentry: Status: #{Sentry.initialized? ? 'OK' : 'Failed'}"

        # Set runtime state
        Onetime::Runtime.update_infrastructure(d9s_enabled: true)
      end
    end
  end
end

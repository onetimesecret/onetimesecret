# lib/onetime/services/system/setup_diagnostics.rb

module Onetime
  module Services
    module System

      ##
      # Diagnostics Provider
      #
      # Configures and initializes Sentry error monitoring and performance
      # tracking for the application. This provider runs early in the service
      # startup sequence to ensure error tracking is available for other
      # providers.
      #
      # Features:
      # - Sentry error monitoring with DSN validation
      # - Performance monitoring with configurable sample rates
      # - Breadcrumb logging for debugging context
      # - Environment-specific configuration
      #
      class SetupDiagnostics < ServiceProvider
        # d9s: diagnostics is a boolean flag. If true, it will enable Sentry
        attr_reader :d9s_enabled

        def initialize
          super(:diagnostics, type: TYPE_INSTANCE, priority: 4) # make Sentry available early
        end

        def start(config)
          @d9s_enabled = config['diagnostics']['enabled'] || false

          return unless d9s_enabled

          backend   = config['diagnostics']['sentry']['backend']
          dsn       = backend['dsn']
          site_host = config['site']['host']

          OT.ld "Setting up Sentry #{backend}..."

          # Log more details about the Sentry configuration for debugging
          OT.ld "[sentry-debug] DSN present: #{!dsn.nil?}"
          OT.ld "[sentry-debug] Site host: #{site_host.inspect}"
          OT.ld "[sentry-debug] OT.env: #{OT.env.inspect}"

          # Early validation to prevent nil errors during initialization
          if dsn.nil?
            OT.ld '[sentry-init] Cannot initialize Sentry with nil DSN'
            @d9s_enabled = false
          elsif site_host.nil?
            OT.le '[sentry-init] Cannot initialize Sentry with nil site_host'
            OT.ld 'Falling back to default environment name'
            site_host = 'unknown-host'
          end

          # Wait to set the state just incase we force it disabled
          set_state(:d9s_enabled, @d9s_enabled)

          # Only proceed if we have valid configuration
          return unless @d9s_enabled

          # Safely log first part of DSN for debugging
          dsn_preview = dsn ? "#{dsn[0..10]}..." : 'nil'
          OT.li "[sentry-init] Initializing with DSN: #{dsn_preview}"

          # Only require Sentry if we have a DSN. We call explicitly
          # via Kernel to aid in testing.
          Kernel.require 'sentry-ruby'
          Kernel.require 'stackprof'

          return_value = Sentry.init do |config|
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
            config.before_send = lambda do |event, _hint|
              # Return nil if the event would cause errors in processing
              if event.nil? || event.request.nil? || event.request.headers.nil?
                OT.ld '[sentry-debug] Filtering out event with nil components'
                return nil
              end

              # Return the event if it passes validation
              event
            end
          end

          set_state(:sentry, Sentry)
          set_state(:sentry_return_value, return_value)
          OT.ld "[sentry-init] Status: #{Sentry.initialized? ? 'OK' : 'Failed'}"
        end
      end

    end
  end
end

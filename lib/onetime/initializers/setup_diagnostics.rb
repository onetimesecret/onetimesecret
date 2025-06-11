# lib/onetime/initializers/setup_diagnostics.rb

module Onetime
  module Initializers
    # d9s: diagnostics is a boolean flag. If true, it will enable Sentry
    attr_accessor :d9s_enabled

    def setup_diagnostics

      OT.d9s_enabled = conf[:diagnostics][:enabled] || false
      return unless OT.d9s_enabled

      backend = conf[:diagnostics][:sentry][:backend]
      dsn = backend.fetch(:dsn, nil)
      site_host = conf.dig(:site, :host)

      OT.ld "Setting up Sentry #{backend}..."

      # Log more details about the Sentry configuration for debugging
      OT.ld "[sentry-debug] DSN present: #{!dsn.nil?}"
      OT.ld "[sentry-debug] Site host: #{site_host.inspect}"
      OT.ld "[sentry-debug] OT.env: #{OT.env.inspect}"

      # Early validation to prevent nil errors during initialization
      if dsn.nil?
        OT.ld '[sentry-init] Cannot initialize Sentry with nil DSN'
        OT.d9s_enabled = false
      elsif site_host.nil?
        OT.le '[sentry-init] Cannot initialize Sentry with nil site_host'
        OT.ld 'Falling back to default environment name'
        site_host = 'unknown-host'
      end

      # Only proceed if we have valid configuration
      return unless OT.d9s_enabled
      # Safely log first part of DSN for debugging
      dsn_preview = dsn ? "#{dsn[0..10]}..." : 'nil'
      OT.li "[sentry-init] Initializing with DSN: #{dsn_preview}"

      # Only require Sentry if we have a DSN. We call explicitly
      # via Kernel to aid in testing.
      Kernel.require 'sentry-ruby'
      Kernel.require 'stackprof'

      Sentry.init do |config|
        config.dsn = dsn
        config.environment = "#{site_host} (#{OT.env})"
        config.release = OT::VERSION.inspect

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

      OT.ld "[sentry-init] Status: #{Sentry.initialized? ? 'OK' : 'Failed'}"

    end
  end
end

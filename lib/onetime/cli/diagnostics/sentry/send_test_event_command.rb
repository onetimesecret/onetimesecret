# lib/onetime/cli/diagnostics/sentry/send_test_event_command.rb
#
# frozen_string_literal: true

# Send a test event to one or both Sentry projects to verify end-to-end delivery.
# Uses sentry-ruby directly with env var DSNs. Runs the background worker
# synchronously so the process does not exit before the event is flushed.
#
# Usage:
#   bin/ots diagnostics sentry send-test-event
#   bin/ots diagnostics sentry send-test-event --backend
#   bin/ots diagnostics sentry send-test-event --frontend
#   bin/ots diagnostics sentry send-test-event --verbose "Custom message"
#   bin/ots diagnostics sentry send-test-event --backend --verbose "Something broke"

require 'socket'

module Onetime
  module CLI
    module Diagnostics
      class SentrySendTestEventCommand < DelayBootCommand
        desc 'Send a test event to Sentry to verify end-to-end delivery'

        argument :message,
          type: :string,
          required: false,
          desc: 'Custom message to include in the test event'

        option :backend,
          type: :boolean,
          default: false,
          desc: 'Send to backend DSN only'

        option :frontend,
          type: :boolean,
          default: false,
          desc: 'Send to frontend DSN only'

        option :verbose,
          type: :boolean,
          default: false,
          aliases: ['v'],
          desc: 'Enable sentry-ruby SDK debug logging'

        def call(message: nil, backend: false, frontend: false, verbose: false, **)
          # Default: send to both when neither flag is given
          send_backend  = backend || (!backend && !frontend)
          send_frontend = frontend || (!backend && !frontend)

          message ||= '[OTS CLI] Test event — verifying Sentry delivery'
          timestamp = Time.now.utc.iso8601
          hostname  = Socket.gethostname

          puts
          puts 'Sentry — Send Test Event'
          puts '=' * 50
          puts format('  Message:   %s', message)
          puts format('  Timestamp: %s', timestamp)
          puts format('  Host:      %s', hostname)
          puts

          send_to_target(:backend, message, verbose: verbose) if send_backend
          send_to_frontend(message, verbose: verbose)         if send_frontend
        end

        private

        def send_to_target(target, message, verbose:)
          dsn    = target == :backend ? Diagnostics.backend_dsn : Diagnostics.frontend_dsn
          label  = target.to_s.capitalize

          puts "#{label} DSN"
          puts '-' * 50

          if dsn.nil?
            puts format('  %-20s %s', 'DSN', '[SKIP] not configured')
            puts
            return
          end

          parsed = Diagnostics.parse_dsn(dsn)
          if parsed.nil?
            puts format('  %-20s %s  invalid DSN format', 'DSN', '[FAIL]')
            puts
            return
          end

          puts format('  %-20s %s...  (project %s)', 'DSN key', parsed[:key][0..7], parsed[:project_id])
          puts format('  %-20s %s', 'Host', parsed[:host])
          puts

          deliver(dsn, label, message, verbose: verbose)
        end

        def send_to_frontend(message, verbose:)
          send_to_target(:frontend, message, verbose: verbose)
        end

        def deliver(dsn, label, message, verbose:)
          require 'sentry-ruby'
          require 'logger'

          Sentry.init do |config|
            config.dsn                       = dsn
            config.environment               = 'cli-test'
            config.release                   = defined?(OT::VERSION) ? OT::VERSION.details : 'cli'
            config.debug                     = verbose
            config.sdk_logger                = Logger.new($stdout) if verbose
            config.traces_sample_rate        = 1.0
            # Synchronous delivery: no background thread, exits cleanly from CLI
            config.background_worker_threads = 0
          end

          start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          event    = Sentry.capture_message(message, level: :warning)
          event_id = event&.event_id
          puts format('  Message sent    event_id=%s', event_id || '(nil — check DSN)')

          begin
            raise "#{message} (test exception)"
          rescue RuntimeError => ex
            exc_event = Sentry.capture_exception(ex)
            exc_id    = exc_event&.event_id
            puts format('  Exception sent  event_id=%s', exc_id || '(nil — check DSN)')
          end

          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
          puts format('  Elapsed: %.2fs', elapsed)
          puts
          puts format("  Check Sentry project %s for events in environment 'cli-test'", label.downcase)
          puts
        rescue StandardError => ex
          puts format('  [FAIL] %s', ex.message)
          puts
        ensure
          # Close and reset so next call can re-initialize with a different DSN
          Sentry.close if Sentry.initialized?
        end
      end
    end

    register 'diagnostics sentry send-test-event', Diagnostics::SentrySendTestEventCommand
  end
end

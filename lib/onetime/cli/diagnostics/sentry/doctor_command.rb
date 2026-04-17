# lib/onetime/cli/diagnostics/sentry/doctor_command.rb
#
# frozen_string_literal: true

require 'time'

# Report on the full Sentry configuration health without booting the
# application. Reads environment variables directly so it works
# before Redis/DB are available.
#
# Usage:
#   bin/ots diagnostics sentry doctor
#   bin/ots diagnostics sentry doctor --send-event
#
# Checks:
#   1. DIAGNOSTICS_ENABLED env var is 'true'
#   2. DSN env vars are set (backend / frontend / workers / fallback)
#   3. DSN format is valid (https://KEY@HOST/PROJECT_ID)
#   4. Sentry host responds at /api/0/  (unauthenticated)
#   5. Store endpoint accepts the DSN key (authenticated POST)
#   6. (--send-event) sentry-ruby SDK raises → captures → delivers

module Onetime
  module CLI
    module Diagnostics
      class SentryDoctorCommand < DelayBootCommand
        desc 'Report Sentry configuration and connectivity health'

        option :send_event,
          type: :boolean,
          default: false,
          desc: 'Also raise/capture a test exception through sentry-ruby to verify SDK delivery'

        TICK  = '[OK]  '
        CROSS = '[FAIL]'
        WARN  = '[WARN]'

        DSN_TARGETS = %w[BACKEND FRONTEND WORKERS].freeze

        def call(send_event: false, **)
          @issues = []

          puts
          puts 'Sentry Configuration Doctor'
          puts '=' * 50

          check_env
          check_dsn(:backend)
          check_dsn(:frontend)
          send_live_events if send_event

          puts
          summarize
        end

        private

        def ok(label, value = nil)
          line  = format('  %-28s %s', label, TICK)
          line += "  #{value}" if value
          puts line
        end

        def fail(label, detail = nil)
          line  = format('  %-28s %s', label, CROSS)
          line += "  #{detail}" if detail
          puts line
          @issues << "#{label}: #{detail}"
        end

        def warn(label, detail = nil)
          line  = format('  %-28s %s', label, WARN)
          line += "  #{detail}" if detail
          puts line
        end

        def check_env
          puts
          puts 'Environment variables'
          puts '-' * 50

          enabled = ENV.fetch('DIAGNOSTICS_ENABLED', nil)
          fail 'DIAGNOSTICS_ENABLED', "#{enabled.inspect} (must be 'true')" unless enabled == 'true'

          ok 'DIAGNOSTICS_ENABLED', enabled

          DSN_TARGETS.each { |target| check_env_dsn(target) }

          ok 'SENTRY_SAMPLE_RATE', ENV['SENTRY_SAMPLE_RATE'] || '0.10'

          log_errors = ENV.fetch('SENTRY_LOG_ERRORS', nil)
          ok 'SENTRY_LOG_ERRORS', log_errors.nil? ? '(default: true)' : log_errors
        end

        def check_env_dsn(target)
          var = "SENTRY_DSN_#{target}"
          val = ENV.fetch(var, nil)

          if val.to_s.strip.empty?
            fail var, 'not set (no SENTRY_DSN fallback either)' if ENV['SENTRY_DSN'].to_s.strip.empty?

            warn var, 'not set — using SENTRY_DSN fallback'

          else
            ok var, 'set'
          end
        end

        def check_dsn(role)
          dsn = role == :backend ? Diagnostics.backend_dsn : Diagnostics.frontend_dsn
          return if dsn.nil?

          label = "#{role.to_s.capitalize} DSN"
          puts
          puts label
          puts '-' * 50

          # Frontend falling back to SENTRY_DSN is identical to backend —
          # no useful second probe, just note it and skip.
          if role == :frontend && dsn == Diagnostics.backend_dsn && ENV['SENTRY_DSN_FRONTEND'].to_s.strip.empty?
            warn label, 'same as backend (SENTRY_DSN fallback) — skipping duplicate probe'
            return
          end

          parsed = Diagnostics.parse_dsn(dsn)
          if parsed.nil?
            fail 'DSN format', 'invalid — expected https://KEY@HOST/PROJECT_ID'
            return
          end

          ok 'Key',        "#{parsed[:key][0..7]}..."
          ok 'Host',       parsed[:host]
          ok 'Project ID', parsed[:project_id]

          backend_parsed = role == :frontend ? Diagnostics.parse_dsn(Diagnostics.backend_dsn) : nil
          if backend_parsed && backend_parsed[:host] == parsed[:host]
            ok 'API connectivity', 'same host as backend (already verified)'
          else
            probe_host(parsed[:host])
          end

          probe_store(parsed)
        end

        def probe_host(host)
          result = Diagnostics.check_api(host)
          if result[:ok]
            ok 'API connectivity', "#{result[:status]} /api/0/"
          else
            detail = result[:error] ? "#{result[:status]} — #{result[:error]}" : result[:status].to_s
            fail 'API connectivity', detail
          end
        end

        def probe_store(parsed)
          result = Diagnostics.check_store(parsed)
          if result[:ok]
            ok 'Store endpoint', "#{result[:status]} POST /api/#{parsed[:project_id]}/store/"
          else
            detail = result[:error] ? "#{result[:status]} — #{result[:error]}" : result[:status].to_s
            fail 'Store endpoint', detail
          end
        end

        # Opt-in: initializes sentry-ruby with synchronous delivery, raises a
        # test exception, captures it, and reports the event_id. Runs for
        # backend and (if distinct) frontend DSNs.
        def send_live_events
          puts
          puts 'Live SDK delivery'
          puts '-' * 50

          deliver_via_sdk(:backend, Diagnostics.backend_dsn)

          frontend = Diagnostics.frontend_dsn
          return if frontend.nil? || frontend == Diagnostics.backend_dsn

          deliver_via_sdk(:frontend, frontend)
        end

        def deliver_via_sdk(role, dsn)
          label = "#{role.to_s.capitalize} SDK delivery"
          return if dsn.nil?

          parsed = Diagnostics.parse_dsn(dsn)
          unless parsed
            fail label, 'invalid DSN'
            return
          end

          require 'sentry-ruby'
          Sentry.close if defined?(Sentry) && Sentry.initialized?

          Sentry.init do |c|
            c.dsn                       = dsn
            c.environment               = 'cli-doctor'
            # Mirror SetupDiagnostics#resolve_sentry_release so doctor-originated
            # events group under the same release as runtime events.
            c.release                   = begin
              env_release = ENV.fetch('SENTRY_RELEASE', '').strip
              if env_release.empty?
                defined?(OT::VERSION) ? OT::VERSION.get_build_info : 'cli'
              else
                env_release
              end
            end
            c.traces_sample_rate        = 0.0
            # Synchronous delivery — CLI exits cleanly after capture.
            c.background_worker_threads = 0
          end

          begin
            raise "[OTS doctor] Sentry delivery probe #{Time.now.utc.iso8601}"
          rescue RuntimeError => ex
            event    = Sentry.capture_exception(ex)
            event_id = event&.event_id
            fail label, 'capture_exception returned nil (dropped by before_send, sample rate, or rate limit)' unless event_id

            ok label, "event_id=#{event_id} (project #{parsed[:project_id]})"
          end
        rescue StandardError => ex
          fail label, ex.message
        ensure
          Sentry.close if defined?(Sentry) && Sentry.initialized?
        end

        def summarize
          puts '=' * 50
          if @issues.empty?
            puts 'Overall: HEALTHY'
          else
            puts "Overall: #{@issues.size} issue(s) found"
            puts
            @issues.each { |i| puts "  - #{i}" }
            puts
            puts 'Fix the issues above and re-run: bin/ots diagnostics sentry doctor'
            exit 1
          end
          puts
        end
      end
    end

    register 'diagnostics sentry doctor', Diagnostics::SentryDoctorCommand
  end
end

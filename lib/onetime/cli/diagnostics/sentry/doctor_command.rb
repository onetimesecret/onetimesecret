# lib/onetime/cli/diagnostics/sentry/doctor_command.rb
#
# frozen_string_literal: true

# Report on the full Sentry configuration health without booting the
# application. Reads environment variables directly so it works
# before Redis/DB are available.
#
# Usage:
#   bin/ots diagnostics sentry doctor
#
# Checks:
#   1. DIAGNOSTICS_ENABLED env var is 'true'
#   2. DSN env vars are set (backend / frontend / fallback)
#   3. DSN format is valid (https://KEY@HOST/PROJECT_ID)
#   4. Sentry host responds at /api/0/  (unauthenticated)
#   5. Store endpoint accepts the DSN key (authenticated POST)

module Onetime
  module CLI
    module Diagnostics
      class SentryDoctorCommand < DelayBootCommand
        desc 'Report Sentry configuration and connectivity health'

        def call(**)
          @issues = []

          puts
          puts 'Sentry Configuration Doctor'
          puts '=' * 50

          check_env
          check_backend_dsn
          check_frontend_dsn

          puts
          summarize
        end

        TICK  = '[OK]  '
        CROSS = '[FAIL]'
        WARN  = '[WARN]'

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

          backend = ENV.fetch('SENTRY_DSN_BACKEND', nil)
          if backend.to_s.strip.empty?
            fallback = ENV.fetch('SENTRY_DSN', nil)
            fail 'SENTRY_DSN_BACKEND', 'not set (no SENTRY_DSN fallback either)' if fallback.to_s.strip.empty?

            warn 'SENTRY_DSN_BACKEND', 'not set — using SENTRY_DSN fallback'

          else
            ok 'SENTRY_DSN_BACKEND', 'set'
          end

          frontend = ENV.fetch('SENTRY_DSN_FRONTEND', nil)
          if frontend.to_s.strip.empty?
            fallback = ENV.fetch('SENTRY_DSN', nil)
            fail 'SENTRY_DSN_FRONTEND', 'not set (no SENTRY_DSN fallback either)' if fallback.to_s.strip.empty?

            warn 'SENTRY_DSN_FRONTEND', 'not set — using SENTRY_DSN fallback'

          else
            ok 'SENTRY_DSN_FRONTEND', 'set'
          end

          sample_rate = ENV['SENTRY_SAMPLE_RATE'] || '0.10'
          ok 'SENTRY_SAMPLE_RATE', sample_rate

          log_errors = ENV.fetch('SENTRY_LOG_ERRORS', nil)
          ok 'SENTRY_LOG_ERRORS', log_errors.nil? ? '(default: true)' : log_errors
        end

        def check_backend_dsn
          dsn = Diagnostics.backend_dsn
          return if dsn.nil?

          puts
          puts 'Backend DSN'
          puts '-' * 50

          parsed = Diagnostics.parse_dsn(dsn)
          if parsed.nil?
            fail 'DSN format', 'invalid — expected https://KEY@HOST/PROJECT_ID'
            return
          end

          ok   'Key',        "#{parsed[:key][0..7]}..."
          ok   'Host',       parsed[:host]
          ok   'Project ID', parsed[:project_id]

          probe_host(parsed[:host])
          probe_store(parsed)
        end

        def check_frontend_dsn
          dsn = Diagnostics.frontend_dsn
          return if dsn.nil?

          # Skip if it's the same DSN as backend (SENTRY_DSN fallback for both)
          if dsn == Diagnostics.backend_dsn && ENV['SENTRY_DSN_FRONTEND'].to_s.strip.empty?
            puts
            puts 'Frontend DSN'
            puts '-' * 50
            warn 'Frontend DSN', 'same as backend (SENTRY_DSN fallback) — skipping duplicate probe'
            return
          end

          puts
          puts 'Frontend DSN'
          puts '-' * 50

          parsed = Diagnostics.parse_dsn(dsn)
          if parsed.nil?
            fail 'DSN format', 'invalid — expected https://KEY@HOST/PROJECT_ID'
            return
          end

          ok 'Key',        "#{parsed[:key][0..7]}..."
          ok 'Host',       parsed[:host]
          ok 'Project ID', parsed[:project_id]

          # Skip connectivity re-probe if on same host as backend
          backend_parsed = Diagnostics.parse_dsn(Diagnostics.backend_dsn)
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

# lib/onetime/cli/diagnostics/sentry/check_dsn_command.rb
#
# frozen_string_literal: true

# Parse and validate an arbitrary Sentry DSN, then probe connectivity
# and authentication without sending a real event.
#
# Usage:
#   bin/ots diagnostics sentry check-dsn https://KEY@HOST/PROJECT_ID
#   bin/ots diagnostics sentry check-dsn "$SENTRY_DSN_BACKEND"

module Onetime
  module CLI
    module Diagnostics
      class SentryCheckDsnCommand < DelayBootCommand
        desc 'Parse and probe a Sentry DSN for validity and connectivity'

        argument :dsn,
          type: :string,
          required: true,
          desc: 'Sentry DSN to check (https://KEY@HOST/PROJECT_ID)'

        def call(dsn:, **)
          puts
          puts 'Sentry DSN Check'
          puts '=' * 50

          parsed = Diagnostics.parse_dsn(dsn)
          if parsed.nil?
            puts
            puts format('  %-20s %s', 'Format', '[FAIL] invalid')
            puts
            puts '  Expected: https://PUBLIC_KEY@hostname/project_id'
            puts "  Got:      #{dsn.inspect}"
            puts
            exit 1
          end

          puts
          puts 'Parsed components'
          puts '-' * 50
          puts format('  %-20s %s', 'Key (public)',  parsed[:key])
          puts format('  %-20s %s', 'Host',          parsed[:host])
          puts format('  %-20s %s', 'Project ID',    parsed[:project_id])
          puts format('  %-20s %s', 'Store URL',     Diagnostics.store_url(parsed))

          puts
          puts 'Connectivity'
          puts '-' * 50

          api_result = Diagnostics.check_api(parsed[:host])
          print format('  %-20s ', 'API /api/0/')
          if api_result[:ok]
            puts format('[OK]    %d', api_result[:status])
          else
            detail = api_result[:error] || api_result[:status].to_s
            puts format('[FAIL]  %s', detail)
          end

          store_result = Diagnostics.check_store(parsed)
          print format('  %-20s ', "Store /api/#{parsed[:project_id]}/")
          if store_result[:ok]
            puts format('[OK]    %d', store_result[:status])
          else
            detail = store_result[:error] || store_result[:status].to_s
            puts format('[FAIL]  %s', detail)
          end

          puts
          puts '=' * 50
          if api_result[:ok] && store_result[:ok]
            puts 'DSN is valid and reachable.'
          else
            puts 'One or more checks failed — see details above.'
            exit 1
          end
          puts
        end
      end
    end

    register 'diagnostics sentry check-dsn', Diagnostics::SentryCheckDsnCommand
  end
end

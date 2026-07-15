# frozen_string_literal: true

#
# SimpleCov configuration, auto-loaded by `require 'simplecov'`.
#
# Produces a Cobertura XML coverage report consumed by GitHub Code Quality.
# Coverage is opt-in via COVERAGE=true so normal/local test runs are
# unaffected. The unit suite runs across several RSpec processes (unit, cli and
# per-app specs), so each process gets a unique command name and SimpleCov
# merges their results into a single coverage/coverage.xml.
if ENV['COVERAGE'] == 'true'
  require 'simplecov-cobertura'

  SimpleCov.command_name "rspec:#{Process.pid}"
  # Keep merged results from earlier RSpec processes valid for the whole job.
  SimpleCov.merge_timeout 3600

  SimpleCov.start do
    add_filter %r{/spec/}
    add_filter %r{/try/}
    add_filter %r{/tryouts/}
    formatter SimpleCov::Formatter::CoberturaFormatter
  end
end

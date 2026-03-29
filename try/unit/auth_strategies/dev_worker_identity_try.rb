# try/unit/auth_strategies/dev_worker_identity_try.rb
#
# frozen_string_literal: true

#
# Tests for DevWorkerIdentity module which provides collision-resistant
# username generation for parallel CI execution.
#
# Tests cover:
# 1. Namespaced username generation with various env vars
# 2. Priority order of env var detection
# 3. Fallback to process-unique suffix
# 4. Collision resistance across different worker IDs

require 'digest'
require_relative '../../../lib/onetime/application/auth_strategies/dev_worker_identity'

@identity = Onetime::Application::AuthStrategies::DevWorkerIdentity

# Store and clear env vars for clean testing
@env_vars = %w[DEV_WORKER_ID GITHUB_JOB TEST_ENV_NUMBER CIRCLE_NODE_INDEX]
@original_env = @env_vars.to_h { |k| [k, ENV[k]] }
@env_vars.each { |k| ENV.delete(k) }
@identity.instance_variable_set(:@process_suffix, nil)

## With no env vars, uses process-unique fallback
@result_fallback = @identity.namespaced_username('alice')
@result_fallback.match?(/^alice_w\d+_\d+$/)
#=> true

## Fallback suffix is cached within process
@identity.instance_variable_set(:@process_suffix, nil)
@result1 = @identity.namespaced_username('alice')
@result2 = @identity.namespaced_username('bob')
@suffix1 = @result1.sub('alice_', '')
@suffix2 = @result2.sub('bob_', '')
@suffix1 == @suffix2
#=> true

## With GITHUB_JOB set, produces deterministic suffix
ENV['GITHUB_JOB'] = 'ruby-integration-simple'
@identity.instance_variable_set(:@process_suffix, nil)
@result_github = @identity.namespaced_username('alice')
@result_github.match?(/^alice_w[a-f0-9]{4}$/)
#=> true

## Same GITHUB_JOB produces same result
ENV['GITHUB_JOB'] = 'ruby-integration-simple'
@r1 = @identity.namespaced_username('alice')
@r2 = @identity.namespaced_username('alice')
@r1 == @r2
#=> true

## Different GITHUB_JOB produces different result
ENV['GITHUB_JOB'] = 'ruby-integration-full-postgres'
@result_postgres = @identity.namespaced_username('alice')
@result_github != @result_postgres
#=> true

## DEV_WORKER_ID takes priority over GITHUB_JOB
ENV['DEV_WORKER_ID'] = 'explicit-worker'
ENV['GITHUB_JOB'] = 'should-be-ignored'
@result_explicit = @identity.namespaced_username('alice')
ENV.delete('DEV_WORKER_ID')
@result_job_only = @identity.namespaced_username('alice')
@result_explicit != @result_job_only
#=> true

## Collision resistance: all four CI jobs produce unique namespaces
@env_vars.each { |k| ENV.delete(k) }
@jobs = %w[
  ruby-integration-simple
  ruby-integration-full-sqlite
  ruby-integration-full-postgres
  ruby-integration-disabled
]
@namespaces = @jobs.map do |job|
  ENV['GITHUB_JOB'] = job
  @identity.namespaced_username('dev_alice')
end
@namespaces.uniq.size == @jobs.size
#=> true

## detect_worker_id returns nil with no env vars
@env_vars.each { |k| ENV.delete(k) }
@identity.detect_worker_id.nil?
#=> true

## detect_worker_id returns GITHUB_JOB when set
ENV['GITHUB_JOB'] = 'test-job'
@identity.detect_worker_id
#=> 'test-job'

## parallel_ci? returns false with no env vars
@env_vars.each { |k| ENV.delete(k) }
@identity.parallel_ci?
#=> false

## parallel_ci? returns true with GITHUB_JOB set
ENV['GITHUB_JOB'] = 'ci-job'
@identity.parallel_ci?
#=> true

## worker_id_for_logging returns 'local' with no env vars
@env_vars.each { |k| ENV.delete(k) }
@identity.worker_id_for_logging
#=> 'local'

## worker_id_for_logging returns job name when set
ENV['GITHUB_JOB'] = 'logging-test-job'
@identity.worker_id_for_logging
#=> 'logging-test-job'

# Cleanup: restore original env
@original_env.each do |key, value|
  if value.nil?
    ENV.delete(key)
  else
    ENV[key] = value
  end
end
@identity.instance_variable_set(:@process_suffix, nil)

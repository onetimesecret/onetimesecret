# spec/integration/integration_spec_helper.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'

# Integration tests use REAL Valkey/Redis on port 2121
# The ConfigureFamilia initializer enforces this for safety (prevents
# accidentally writing to production Redis on default port 6379).
#
# To run integration tests:
#   pnpm run test:database:start  # Start Valkey on port 2121
#   pnpm run test:rspec:failures spec/integration/
#
# FakeRedis is NOT used for integration tests because:
# 1. Integration tests require full application boot (Onetime.boot!)
# 2. Rodauth requires real database transactions
# 3. Session storage needs real Redis operations
# 4. FakeRedis 0.1.4 is incompatible with Redis 5.x client

RSpec.configure do |config|
  config.include Rack::Test::Methods, type: :request
  config.include Rack::Test::Methods, type: :integration

  # Parse Redis URI once at configuration time for robust port checking
  redis_uri_string = OT.conf&.dig('redis', 'uri')
  test_redis_port = begin
    URI.parse(redis_uri_string).port if redis_uri_string
  rescue URI::InvalidURIError
    nil
  end

  # Clean Valkey database before all integration tests in a group
  # Skip if :shared_db_state metadata is set (for specs using before(:all) shared setup)
  # Skip if :billing metadata is set (billing tests manage their own plan data)
  config.before(:all, type: :integration) do |context|
    next if context.class.metadata[:shared_db_state]
    next if context.class.metadata[:billing]

    if test_redis_port == 2121
      begin
        Familia.dbclient.flushdb
      rescue StandardError => e
        warn "Failed to clean test database before all: #{e.message}"
        warn e.backtrace.join("\n") if ENV['ONETIME_DEBUG']
      end
    end
  end

  # Clean Valkey database before each integration test
  # Skip if :shared_db_state metadata is set (for specs using before(:all) shared setup)
  # Skip if :billing metadata is set (billing tests manage their own plan data)
  config.before(:each, type: :integration) do |example|
    next if example.metadata[:shared_db_state]
    next if example.metadata[:billing]

    if test_redis_port == 2121
      begin
        Familia.dbclient.flushdb
      rescue StandardError => e
        warn "Failed to clean test database: #{e.message}"
        warn e.backtrace.join("\n") if ENV['ONETIME_DEBUG']
      end
    end
  end

  # NOTE: after(:each) cleanup is handled centrally in spec/spec_helper.rb
  # to ensure ALL integration tests get cleanup regardless of which helper they load.
end

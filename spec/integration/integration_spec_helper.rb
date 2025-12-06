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

  redis_conf = OT.conf&.fetch('redis')
  redis_uri = redis.conf&.uri

  # Clean Valkey database before all integration tests in a group
  config.before(:all, type: :integration) do
    if redis_uri&.include?(':2121')
      begin
        # Use the real Familia client to flush the test database
        Familia.dbclient.flushdb
      rescue StandardError => e
        warn "Failed to clean test database before all: #{e.message}" if ENV['DEBUG']
      end
    end
  end

  # Clean Valkey database before each integration test
  config.before(:each, type: :integration) do
    if redis_uri&.include?(':2121')
      begin
        # Use the real Familia client to flush the test database
        Familia.dbclient.flushdb
      rescue StandardError => e
        warn "Failed to clean test database: #{e.message}" if ENV['DEBUG']
      end
    end
  end

  # Clean up after integration tests
  config.after(:each, type: :integration) do
    if redis_uri&.include?(':2121')
      begin
        Familia.dbclient.flushdb
      rescue StandardError => e
        warn "Failed to clean test database: #{e.message}" if ENV['DEBUG']
      end
    end
  end
end

# spec/integration/integration_spec_helper.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'

# Load FakeRedis and stub Redis connections globally for integration tests
require 'fakeredis'

# Monkey-patch FakeRedis to add missing methods that real Redis has
class FakeRedis::Redis
  # Add close method that Redis clients have
  def close
    # FakeRedis doesn't need to close connections, but we add this
    # method for compatibility with code that expects it
  end
end

RSpec.configure do |config|
  config.include Rack::Test::Methods, type: :request
  config.include Rack::Test::Methods, type: :integration

  # Apply FakeRedis mocking to both :request and :integration type tests
  config.before(:each, type: :request) do
    # Use FakeRedis for integration tests
    # Create a fake Redis client
    redis_client = FakeRedis::Redis.new

    # Mock Familia database client
    allow(Familia).to receive(:dbclient).and_return(redis_client)

    # Mock Redis connection creation
    allow(Redis).to receive(:new).and_return(redis_client)

    # Mock OT database pool
    fake_pool = double('ConnectionPool')
    allow(fake_pool).to receive(:with).and_yield(redis_client)
    allow(OT).to receive(:database_pool).and_return(fake_pool)
  end

  config.before(:each, type: :integration) do
    # Use FakeRedis for integration tests
    # Create a fake Redis client
    redis_client = FakeRedis::Redis.new

    # Mock Familia database client
    allow(Familia).to receive(:dbclient).and_return(redis_client)

    # Mock Redis connection creation
    allow(Redis).to receive(:new).and_return(redis_client)

    # Mock OT database pool
    fake_pool = double('ConnectionPool')
    allow(fake_pool).to receive(:with).and_yield(redis_client)
    allow(fake_pool).to receive(:ping).and_return('PONG')
    allow(OT).to receive(:database_pool).and_return(fake_pool)
  end

  config.after(:each, type: :request) do
    # Clean up FakeRedis after each test
    begin
      FakeRedis::Redis.new.flushdb
    rescue
      # Ignore cleanup errors
    end
  end

  config.after(:each, type: :integration) do
    # Clean up FakeRedis after each test
    begin
      FakeRedis::Redis.new.flushdb
    rescue
      # Ignore cleanup errors
    end
  end
end

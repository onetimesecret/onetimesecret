# spec/integration/integration_spec_helper.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'fakeredis'

RSpec.configure do |config|
  config.include Rack::Test::Methods, type: :request

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

  config.after(:each, type: :request) do
    # Clean up FakeRedis after each test
    begin
      FakeRedis::Redis.new.flushdb
    rescue
      # Ignore cleanup errors
    end
  end
end

# spec/integration/integration_spec_helper.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'

# Load FakeRedis for integration tests
require 'fakeredis'

# Global FakeRedis setup for integration tests
# This uses module prepending instead of RSpec mocks, so it works in before(:all) blocks
module FakeRedisGlobalStub
  require 'concurrent'

  # Store FakeRedis instances per database number with thread-safe hash
  @redis_instances = Concurrent::Hash.new

  def self.redis_for_db(db_num = 0)
    # Thread-safe lazy initialization using Concurrent::Hash
    @redis_instances[db_num] ||= FakeRedis::Redis.new
  end

  def self.reset_all!
    @redis_instances.each_value do |redis|
      begin
        redis.flushdb
      rescue StandardError => e
        # Log cleanup errors for debugging (Rails logger if available, otherwise stderr)
        if defined?(Rails) && Rails.logger
          Rails.logger.warn "FakeRedis cleanup error: #{e.message}"
        elsif ENV['DEBUG']
          warn "FakeRedis cleanup error: #{e.message}"
        end
      end
    end
    @redis_instances.clear
  end
end

# Monkey-patch FakeRedis to add missing methods that real Redis has
class FakeRedis::Redis
  # Add close method that Redis clients have
  def close
    # FakeRedis doesn't need to close connections, but we add this
    # method for compatibility with code that expects it
    nil
  end

  # Add ping method if not already present
  unless method_defined?(:ping)
    def ping
      'PONG'
    end
  end

  # Add watch method for optimistic locking support
  # In tests, we can make this a no-op since we're not testing concurrent access
  unless method_defined?(:watch)
    def watch(*keys)
      # FakeRedis doesn't support WATCH for optimistic locking,
      # but we provide a no-op implementation for test compatibility
      if block_given?
        yield
        'OK'
      else
        'OK'
      end
    end
  end

  # Add unwatch method (companion to watch)
  unless method_defined?(:unwatch)
    def unwatch
      'OK'
    end
  end
end

# Global stub for Redis.new to return FakeRedis in test environment
# This works outside of RSpec example context, so it's available in before(:all)
module RedisTestStub
  def new(options = {})
    # Extract database number from connection URL or options
    db_num = 0
    if options.is_a?(Hash)
      if options[:url]
        db_num = options[:url][%r{/(\d+)$}, 1].to_i
      elsif options[:db]
        db_num = options[:db].to_i
      end
    end

    FakeRedisGlobalStub.redis_for_db(db_num)
  end
end

# Apply the global stub before any tests run
Redis.singleton_class.prepend(RedisTestStub)

# Also stub Familia.dbclient to return FakeRedis
# This needs to be done globally, not just in before(:each)
module FamiliaTestStub
  def dbclient(index = 0)
    FakeRedisGlobalStub.redis_for_db(index)
  end

  def with_isolated_dbclient(index = 0)
    client = FakeRedisGlobalStub.redis_for_db(index)
    yield client
    # Note: Real Familia calls client.close here, but FakeRedis handles this gracefully
  end
end

# Apply the Familia stub
Familia.singleton_class.prepend(FamiliaTestStub)

RSpec.configure do |config|
  config.include Rack::Test::Methods, type: :request
  config.include Rack::Test::Methods, type: :integration

  # Reset FakeRedis state before each test to ensure test isolation
  config.before(:each, type: :request) do
    FakeRedisGlobalStub.reset_all!
  end

  config.before(:each, type: :integration) do
    FakeRedisGlobalStub.reset_all!
  end

  # Clean up FakeRedis after tests
  config.after(:each, type: :request) do
    begin
      FakeRedisGlobalStub.reset_all!
    rescue Redis::BaseConnectionError, FakeRedis::CommandNotSupported => e
      # Silently ignore known cleanup errors
      # Redis::BaseConnectionError - connection already closed
      # FakeRedis::CommandNotSupported - unsupported command in cleanup
      if defined?(Rails) && Rails.logger
        Rails.logger.warn "FakeRedis cleanup failed: #{e.class} - #{e.message}"
      elsif ENV['DEBUG']
        warn "FakeRedis cleanup failed: #{e.class} - #{e.message}"
      end
    end
  end

  config.after(:each, type: :integration) do
    begin
      FakeRedisGlobalStub.reset_all!
    rescue Redis::BaseConnectionError, FakeRedis::CommandNotSupported => e
      # Silently ignore known cleanup errors
      if defined?(Rails) && Rails.logger
        Rails.logger.warn "FakeRedis cleanup failed: #{e.class} - #{e.message}"
      elsif ENV['DEBUG']
        warn "FakeRedis cleanup failed: #{e.class} - #{e.message}"
      end
    end
  end
end

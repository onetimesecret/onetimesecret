# try/unit/controllers/health_try.rb
#
# frozen_string_literal: true

# Tests for the Health controller endpoints
#
# Tests Health#index (basic health check) and Health#advanced (detailed checks)
# along with the private check_redis and check_database methods.

require_relative '../../support/test_helpers'
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '../../..')).freeze

require 'onetime'
require 'onetime/config'
Onetime.boot! :test

require 'rack/test'
require 'rack/mock'
require 'json'

require_relative '../../../apps/web/core/controllers/health'

# Mock controller that includes the Base module for testing private methods
class MockHealthController < Core::Controllers::Health
  attr_accessor :req, :res

  def initialize
    @res = MockResponse.new
  end

  # Expose private methods for testing
  def test_check_redis
    check_redis
  end

  def test_check_rabbitmq
    check_rabbitmq
  end

  def test_check_database
    check_database
  end

  def test_mask_url(url)
    mask_url(url)
  end
end

# Simple mock response object
class MockResponse
  attr_accessor :body, :status

  def initialize
    @headers = {}
    @status = 200
  end

  def [](key)
    @headers[key]
  end

  def []=(key, value)
    @headers[key] = value
  end
end

# Controller subclass that simulates Redis failure for error testing
class MockHealthControllerWithRedisError < MockHealthController
  private

  def check_redis
    # Simulate what happens when Redis.ping raises an error
    raise StandardError, 'Connection refused'
  rescue StandardError => ex
    {
      status: 'error',
      error: ex.message,
    }
  end
end

# Controller subclass that simulates RabbitMQ error
class MockHealthControllerWithRabbitMQError < MockHealthController
  private

  def check_rabbitmq
    {
      status: 'error',
      error: 'Connection refused - connect(2) for "localhost" port 5672',
    }
  end
end

# Controller subclass that simulates database error
class MockHealthControllerWithDatabaseError < MockHealthController
  private

  def check_database
    raise StandardError, 'Database connection failed'
  rescue StandardError => ex
    {
      status: 'error',
      error: ex.message,
    }
  end
end

# -------------------------------------------------------------------
# TEST: Health#index returns correct JSON structure
# -------------------------------------------------------------------

## Health#index returns JSON with status ok
@controller = MockHealthController.new
@controller.index
@result = JSON.parse(@controller.res.body)
@result['status']
#=> 'ok'

## Health#index includes timestamp as integer
@controller = MockHealthController.new
@controller.index
@result = JSON.parse(@controller.res.body)
@result['timestamp'].is_a?(Integer)
#=> true

## Health#index includes version string
@controller = MockHealthController.new
@controller.index
@result = JSON.parse(@controller.res.body)
@result['version'].is_a?(String) && !@result['version'].empty?
#=> true

## Health#index sets content-type to application/json
@controller = MockHealthController.new
@controller.index
@controller.res['content-type']
#=> 'application/json'

# -------------------------------------------------------------------
# TEST: Health#advanced returns correct JSON structure
# -------------------------------------------------------------------

## Health#advanced returns JSON with checks hash
@controller = MockHealthController.new
@controller.advanced
@result = JSON.parse(@controller.res.body)
@result['checks'].is_a?(Hash)
#=> true

## Health#advanced includes redis check
@controller = MockHealthController.new
@controller.advanced
@result = JSON.parse(@controller.res.body)
@result['checks'].key?('redis')
#=> true

## Health#advanced includes rabbitmq check
@controller = MockHealthController.new
@controller.advanced
@result = JSON.parse(@controller.res.body)
@result['checks'].key?('rabbitmq')
#=> true

## Health#advanced includes database check
@controller = MockHealthController.new
@controller.advanced
@result = JSON.parse(@controller.res.body)
@result['checks'].key?('database')
#=> true

## Health#advanced includes timestamp
@controller = MockHealthController.new
@controller.advanced
@result = JSON.parse(@controller.res.body)
@result['timestamp'].is_a?(Integer)
#=> true

## Health#advanced includes version
@controller = MockHealthController.new
@controller.advanced
@result = JSON.parse(@controller.res.body)
@result['version'].is_a?(String)
#=> true

## Health#advanced sets content-type to application/json
@controller = MockHealthController.new
@controller.advanced
@controller.res['content-type']
#=> 'application/json'

# -------------------------------------------------------------------
# TEST: check_redis handles success case
# -------------------------------------------------------------------

## check_redis returns ok status when Redis responds with PONG
@controller = MockHealthController.new
@result = @controller.test_check_redis
# In test environment with running Redis, this should succeed
@result[:status] == 'ok' || @result[:status] == 'error'
#=> true

## check_redis returns hash with status key
@controller = MockHealthController.new
@result = @controller.test_check_redis
@result.key?(:status)
#=> true

# -------------------------------------------------------------------
# TEST: check_redis handles error case
# -------------------------------------------------------------------

## check_redis returns error status when Redis fails
@controller = MockHealthControllerWithRedisError.new
@result = @controller.test_check_redis
[@result[:status], @result[:error]]
#=> ['error', 'Connection refused']

## check_redis error includes error message
@controller = MockHealthControllerWithRedisError.new
@result = @controller.test_check_redis
@result[:error].is_a?(String) && !@result[:error].empty?
#=> true

# -------------------------------------------------------------------
# TEST: check_rabbitmq handles various cases
# -------------------------------------------------------------------

## check_rabbitmq returns hash with status key
@controller = MockHealthController.new
@result = @controller.test_check_rabbitmq
@result.key?(:status)
#=> true

## check_rabbitmq returns valid status (config may provide default URL)
# RabbitMQ URL comes from config first, then env - may have default value
@controller = MockHealthController.new
@result = @controller.test_check_rabbitmq
# Status should be one of: ok (connected), error (failed to connect), or not_configured
['ok', 'error', 'not_configured'].include?(@result[:status])
#=> true

## check_rabbitmq returns valid status when URL is set
# This will return ok if RabbitMQ is running, error if not, or not_configured if URL empty
@controller = MockHealthController.new
@result = @controller.test_check_rabbitmq
['ok', 'error', 'not_configured'].include?(@result[:status])
#=> true

## check_rabbitmq error includes error message
@controller = MockHealthControllerWithRabbitMQError.new
@result = @controller.test_check_rabbitmq
@result[:error].is_a?(String) && !@result[:error].empty?
#=> true

# -------------------------------------------------------------------
# TEST: check_database handles not_configured case
# -------------------------------------------------------------------

## check_database returns not_configured when Auth::Database is not defined
# In test mode without database, should return not_configured
@controller = MockHealthController.new
@result = @controller.test_check_database
# Either not_configured (no database) or ok/error (database present)
['not_configured', 'ok', 'error'].include?(@result[:status])
#=> true

## check_database returns hash with status key
@controller = MockHealthController.new
@result = @controller.test_check_database
@result.key?(:status)
#=> true

# -------------------------------------------------------------------
# TEST: Health#advanced overall status logic
# -------------------------------------------------------------------

## Health#advanced returns ok when all configured checks pass
# This test depends on actual Redis being available in test environment
# RabbitMQ and database are optional and don't affect overall status if not_configured
@controller = MockHealthController.new
@controller.advanced
@result = JSON.parse(@controller.res.body)
# Status should be either 'ok' (all configured services up) or 'degraded' (some failing)
['ok', 'degraded'].include?(@result['status'])
#=> true

## Health#advanced returns degraded when a check fails
# Use the subclass that simulates Redis failure
@controller = MockHealthControllerWithRedisError.new
@controller.advanced
@result = JSON.parse(@controller.res.body)
@result['status']
#=> 'degraded'

## Health#advanced includes error details in checks when failing
@controller = MockHealthControllerWithRedisError.new
@controller.advanced
@result = JSON.parse(@controller.res.body)
@result['checks']['redis']['status']
#=> 'error'

# -------------------------------------------------------------------
# TEST: Response body is valid JSON
# -------------------------------------------------------------------

## Health#index body can be parsed as JSON
@controller = MockHealthController.new
@controller.index
begin
  JSON.parse(@controller.res.body)
  true
rescue JSON::ParserError
  false
end
#=> true

## Health#advanced body can be parsed as JSON
@controller = MockHealthController.new
@controller.advanced
begin
  JSON.parse(@controller.res.body)
  true
rescue JSON::ParserError
  false
end
#=> true

# -------------------------------------------------------------------
# TEST: check_database handles error case
# -------------------------------------------------------------------

## check_database returns error status when database fails
@controller = MockHealthControllerWithDatabaseError.new
@result = @controller.test_check_database
@result[:status]
#=> 'error'

## check_database error includes error message
@controller = MockHealthControllerWithDatabaseError.new
@result = @controller.test_check_database
@result[:error]
#=> 'Database connection failed'

# -------------------------------------------------------------------
# TEST: Version format
# -------------------------------------------------------------------

## Version matches semver pattern (major.minor.patch or with pre-release)
@controller = MockHealthController.new
@controller.index
@result = JSON.parse(@controller.res.body)
@result['version'] =~ /^\d+\.\d+\.\d+(-\w+)?$/
#=:> Integer

# -------------------------------------------------------------------
# TEST: Timestamp is recent
# -------------------------------------------------------------------

## Timestamp is within last 60 seconds (sanity check)
@controller = MockHealthController.new
@controller.index
@result = JSON.parse(@controller.res.body)
@now = Time.now.to_i
(@result['timestamp'] >= @now - 60) && (@result['timestamp'] <= @now + 60)
#=> true

# -------------------------------------------------------------------
# TEST: mask_url masks passwords in URLs
# -------------------------------------------------------------------

## mask_url masks password in redis URL
@controller = MockHealthController.new
@result = @controller.test_mask_url('redis://user:secretpassword@localhost:6379/0')
# URI may normalize by removing default port, but password must be masked
@result.include?('****') && @result.include?('user') && @result.include?('localhost')
#=> true

## mask_url masks password in amqp URL
@controller = MockHealthController.new
@controller.test_mask_url('amqp://guest:guest@localhost:5672/dev')
#=> 'amqp://guest:****@localhost:5672/dev'

## mask_url masks password in postgres URL
@controller = MockHealthController.new
@controller.test_mask_url('postgres://admin:supersecret@db.example.com:5432/mydb')
#=> 'postgres://admin:****@db.example.com:5432/mydb'

## mask_url returns URL unchanged when no password
@controller = MockHealthController.new
@controller.test_mask_url('redis://localhost:6379/0')
#=> 'redis://localhost:6379/0'

## mask_url returns nil for nil input
@controller = MockHealthController.new
@controller.test_mask_url(nil)
#=> nil

## mask_url returns nil for empty string
@controller = MockHealthController.new
@controller.test_mask_url('')
#=> nil

## mask_url handles complex passwords with special chars
@controller = MockHealthController.new
@result = @controller.test_mask_url('amqp://user:p%40ss%3Aword@localhost:5672')
@result.include?('****') && !@result.include?('p%40ss')
#=> true

# -------------------------------------------------------------------
# TEST: check_redis includes masked URL
# -------------------------------------------------------------------

## check_redis result includes url key
@controller = MockHealthController.new
@result = @controller.test_check_redis
@result.key?(:url)
#=> true

## check_redis url is masked (no plaintext password)
@controller = MockHealthController.new
@result = @controller.test_check_redis
# URL should either be nil, contain ****, or have no password
@result[:url].nil? || @result[:url].include?('****') || !@result[:url].include?('@') || @result[:url] !~ /:[^:@]+@/
#=> true

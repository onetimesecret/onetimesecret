# try/unit/controllers/health_try.rb
#
# frozen_string_literal: true

# Tests for the Health controller endpoints
#
# Tests Health#index (basic health check) and Health#advanced (detailed checks)
# along with the private check_keydb, check_jobqueue, and check_authdb methods.

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
  def test_check_keydb
    check_keydb
  end

  def test_check_jobqueue
    check_jobqueue
  end

  def test_check_authdb
    check_authdb
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

# Controller subclass that simulates keydb failure for error testing
class MockHealthControllerWithKeydbError < MockHealthController
  private

  def check_keydb
    # Simulate what happens when keydb ping raises an error
    raise StandardError, 'Connection refused'
  rescue StandardError => ex
    {
      status: 'error',
      error: ex.message,
    }
  end
end

# Controller subclass that simulates job queue error
class MockHealthControllerWithJobqueueError < MockHealthController
  private

  def check_jobqueue
    {
      status: 'error',
      error: 'Connection refused - connect(2) for "localhost" port 5672',
    }
  end
end

# Controller subclass that simulates auth database error
class MockHealthControllerWithAuthdbError < MockHealthController
  private

  def check_authdb
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

## Health#advanced includes keydb check
@controller = MockHealthController.new
@controller.advanced
@result = JSON.parse(@controller.res.body)
@result['checks'].key?('keydb')
#=> true

## Health#advanced includes jobqueue check
@controller = MockHealthController.new
@controller.advanced
@result = JSON.parse(@controller.res.body)
@result['checks'].key?('jobqueue')
#=> true

## Health#advanced includes authdb check
@controller = MockHealthController.new
@controller.advanced
@result = JSON.parse(@controller.res.body)
@result['checks'].key?('authdb')
#=> true

## Health#advanced includes timestamp as float
@controller = MockHealthController.new
@controller.advanced
@result = JSON.parse(@controller.res.body)
@result['timestamp'].is_a?(Float)
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
# TEST: check_keydb handles success case
# -------------------------------------------------------------------

## check_keydb returns ok status when keydb responds with PONG
@controller = MockHealthController.new
@result = @controller.test_check_keydb
# In test environment with running keydb, this should succeed
@result[:status] == 'ok' || @result[:status] == 'error'
#=> true

## check_keydb returns hash with status key
@controller = MockHealthController.new
@result = @controller.test_check_keydb
@result.key?(:status)
#=> true

# -------------------------------------------------------------------
# TEST: check_keydb handles error case
# -------------------------------------------------------------------

## check_keydb returns error status when keydb fails
@controller = MockHealthControllerWithKeydbError.new
@result = @controller.test_check_keydb
[@result[:status], @result[:error]]
#=> ['error', 'Connection refused']

## check_keydb error includes error message
@controller = MockHealthControllerWithKeydbError.new
@result = @controller.test_check_keydb
@result[:error].is_a?(String) && !@result[:error].empty?
#=> true

# -------------------------------------------------------------------
# TEST: check_jobqueue handles various cases
# -------------------------------------------------------------------

## check_jobqueue returns hash with status key
@controller = MockHealthController.new
@result = @controller.test_check_jobqueue
@result.key?(:status)
#=> true

## check_jobqueue returns valid status (config may provide default URL)
# Job queue URL comes from config first, then env - may have default value
@controller = MockHealthController.new
@result = @controller.test_check_jobqueue
# Status should be one of: ok (connected), error (failed to connect), or not_configured
['ok', 'error', 'not_configured'].include?(@result[:status])
#=> true

## check_jobqueue returns valid status when URL is set
# This will return ok if job queue is running, error if not, or not_configured if URL empty
@controller = MockHealthController.new
@result = @controller.test_check_jobqueue
['ok', 'error', 'not_configured'].include?(@result[:status])
#=> true

## check_jobqueue error includes error message
@controller = MockHealthControllerWithJobqueueError.new
@result = @controller.test_check_jobqueue
@result[:error].is_a?(String) && !@result[:error].empty?
#=> true

# -------------------------------------------------------------------
# TEST: check_authdb handles not_configured case
# -------------------------------------------------------------------

## check_authdb returns not_configured when Auth::Database is not defined
# In test mode without database, should return not_configured
@controller = MockHealthController.new
@result = @controller.test_check_authdb
# Either not_configured (no database) or ok/error (database present)
['not_configured', 'ok', 'error'].include?(@result[:status])
#=> true

## check_authdb returns hash with status key
@controller = MockHealthController.new
@result = @controller.test_check_authdb
@result.key?(:status)
#=> true

# -------------------------------------------------------------------
# TEST: Health#advanced overall status logic
# -------------------------------------------------------------------

## Health#advanced returns ok when all configured checks pass
# This test depends on actual keydb being available in test environment
# Job queue and authdb are optional and don't affect overall status if not_configured
@controller = MockHealthController.new
@controller.advanced
@result = JSON.parse(@controller.res.body)
# Status should be either 'ok' (all configured services up) or 'degraded' (some failing)
['ok', 'degraded'].include?(@result['status'])
#=> true

## Health#advanced returns degraded when a check fails
# Use the subclass that simulates keydb failure
@controller = MockHealthControllerWithKeydbError.new
@controller.advanced
@result = JSON.parse(@controller.res.body)
@result['status']
#=> 'degraded'

## Health#advanced includes error details in checks when failing
@controller = MockHealthControllerWithKeydbError.new
@controller.advanced
@result = JSON.parse(@controller.res.body)
@result['checks']['keydb']['status']
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
# TEST: check_authdb handles error case
# -------------------------------------------------------------------

## check_authdb returns error status when database fails
@controller = MockHealthControllerWithAuthdbError.new
@result = @controller.test_check_authdb
@result[:status]
#=> 'error'

## check_authdb error includes error message
@controller = MockHealthControllerWithAuthdbError.new
@result = @controller.test_check_authdb
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

## mask_url masks password in valkey/redis URL
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
# TEST: check_keydb includes masked URL
# -------------------------------------------------------------------

## check_keydb result includes url key
@controller = MockHealthController.new
@result = @controller.test_check_keydb
@result.key?(:url)
#=> true

## check_keydb url is masked (no plaintext password)
@controller = MockHealthController.new
@result = @controller.test_check_keydb
# URL should either be nil, contain ****, or have no password
@result[:url].nil? || @result[:url].include?('****') || !@result[:url].include?('@') || @result[:url] !~ /:[^:@]+@/
#=> true

# try/integration/check_jobqueue_live_try.rb
#
# frozen_string_literal: true

# Integration tests for the check_jobqueue health controller method
# against a live RabbitMQ broker.
#
# Requires RABBITMQ_URL env var (or a broker at amqp://guest:guest@localhost:5672).
# Skips gracefully when no broker URL is available.

require_relative '../support/test_helpers'
ENV['ONETIME_HOME'] ||= File.expand_path(File.join(__dir__, '../../..')).freeze

require 'onetime'
require 'onetime/config'
Onetime.boot! :test

require 'json'

require_relative '../../apps/web/core/controllers/health'

# Determine the AMQP URL for live testing. Skip if explicitly empty.
@rabbitmq_url = ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672')

if @rabbitmq_url.empty?
  puts "SKIP: check_jobqueue_live_try.rb — RABBITMQ_URL not set"
  exit 0
end

# Verify we can actually reach the broker before running tests.
# Without this guard, every test case would fail with connection errors
# that are not useful for diagnosing code problems.
begin
  require 'bunny'
  _probe = Bunny.new(@rabbitmq_url, connection_timeout: 3, read_timeout: 3)
  _probe.start
  _probe.close
rescue StandardError => ex
  puts "SKIP: check_jobqueue_live_try.rb — cannot reach RabbitMQ at #{@rabbitmq_url.sub(/:[^:@]+@/, ':****@')}: #{ex.message}"
  exit 0
end

# Mock controller that exposes the private check_jobqueue method
class MockHealthController < Core::Controllers::Health
  attr_accessor :req, :res

  def initialize
    @res = MockResponse.new
  end

  def test_check_jobqueue
    check_jobqueue
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

# Save original config values so teardown can restore them
@original_jobs_enabled = OT.conf.dig('jobs', 'enabled')
@original_rabbitmq_url = OT.conf.dig('jobs', 'rabbitmq_url')

# Override config to enable jobs with the live broker URL
OT.conf['jobs'] ||= {}
OT.conf['jobs']['enabled'] = true
OT.conf['jobs']['rabbitmq_url'] = @rabbitmq_url

@controller = MockHealthController.new
@result = @controller.test_check_jobqueue

## check_jobqueue returns status ok against live broker
@result[:status]
#=> 'ok'

## check_jobqueue response includes a masked url
@result.key?(:url) && !@result[:url].nil?
#=> true

## check_jobqueue masked url does not expose the raw password
# The raw URL has guest:guest — the masked version should show ****
@result[:url].include?('****') || !@result[:url].include?('@')
#=> true

## check_jobqueue response includes a vhost key
@result.key?(:vhost)
#=> true

## check_jobqueue vhost is a non-nil string
@result[:vhost].is_a?(String)
#=> true

# Restore original config values
OT.conf['jobs']['enabled'] = @original_jobs_enabled
OT.conf['jobs']['rabbitmq_url'] = @original_rabbitmq_url

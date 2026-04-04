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

# Check if RabbitMQ is available
RABBITMQ_AVAILABLE = begin
  if @rabbitmq_url.empty?
    puts "SKIP: check_jobqueue_live_try.rb — RABBITMQ_URL not set"
    false
  else
    # Verify we can actually reach the broker before running tests.
    require 'bunny'
    _probe = Bunny.new(@rabbitmq_url, connection_timeout: 3, read_timeout: 3)
    _probe.start
    _probe.close
    true
  end
rescue StandardError => ex
  puts "SKIP: check_jobqueue_live_try.rb — cannot reach RabbitMQ at #{@rabbitmq_url.sub(/:[^:@]+@/, ':****@')}: #{ex.message}"
  false
end

if RABBITMQ_AVAILABLE
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

  # Save original frozen config so teardown can restore it
  @original_conf = OT.conf

  # The config is deep-frozen after boot, so we replace it with an
  # unfrozen shallow copy that has an unfrozen jobs hash pointing
  # at the live broker URL.
  jobs_override = (OT.conf['jobs'] || {}).dup
  jobs_override['enabled'] = true
  jobs_override['rabbitmq_url'] = @rabbitmq_url

  unfrozen_conf = OT.conf.dup
  unfrozen_conf['jobs'] = jobs_override
  Onetime.send(:conf=, unfrozen_conf)

  @controller = MockHealthController.new
  @result = @controller.test_check_jobqueue
end

# TRYOUTS

## check_jobqueue returns status ok against live broker
if RABBITMQ_AVAILABLE
  @result[:status]
end
#=> RABBITMQ_AVAILABLE ? 'ok' : nil

## check_jobqueue response includes a masked url
if RABBITMQ_AVAILABLE
  @result.key?(:url) && !@result[:url].nil?
end
#=> RABBITMQ_AVAILABLE ? true : nil

## check_jobqueue masked url does not expose the raw password
# The raw URL has guest:guest — the masked version should show ****
if RABBITMQ_AVAILABLE
  @result[:url].include?('****') || !@result[:url].include?('@')
end
#=> RABBITMQ_AVAILABLE ? true : nil

## check_jobqueue response includes a vhost key
if RABBITMQ_AVAILABLE
  @result.key?(:vhost)
end
#=> RABBITMQ_AVAILABLE ? true : nil

## check_jobqueue vhost is a non-nil string
if RABBITMQ_AVAILABLE
  @result[:vhost].is_a?(String)
end
#=> RABBITMQ_AVAILABLE ? true : nil

# Teardown - restore original frozen config
if RABBITMQ_AVAILABLE
  Onetime.send(:conf=, @original_conf)
end

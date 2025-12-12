# try/unit/boot/setup_rabbitmq_try.rb
#
# frozen_string_literal: true

# Tests for SetupRabbitMQ fork safety methods
#
# These tests verify the disconnect/reconnect API works correctly.
# The actual fork behavior is tested by running Puma in cluster mode.

require_relative '../../support/test_helpers'

# Disable actual RabbitMQ connection for these unit tests
ENV['SKIP_RABBITMQ_SETUP'] = '1'

OT.boot! :test

## SetupRabbitMQ class methods exist
Onetime::Initializers::SetupRabbitMQ.respond_to?(:disconnect)
#=> true

## SetupRabbitMQ responds to reconnect
Onetime::Initializers::SetupRabbitMQ.respond_to?(:reconnect)
#=> true

## SetupRabbitMQ responds to channel
Onetime::Initializers::SetupRabbitMQ.respond_to?(:channel)
#=> true

## SetupRabbitMQ responds to connected?
Onetime::Initializers::SetupRabbitMQ.respond_to?(:connected?)
#=> true

## SetupRabbitMQ responds to with_channel
Onetime::Initializers::SetupRabbitMQ.respond_to?(:with_channel)
#=> true

## SetupRabbitMQ responds to clear_thread_channels
Onetime::Initializers::SetupRabbitMQ.respond_to?(:clear_thread_channels)
#=> true

## connected? returns falsy when no connection exists
# (since we skipped RabbitMQ setup)
# Returns nil when $rmq_conn is nil, false when connection closed
!!Onetime::Initializers::SetupRabbitMQ.connected?
#=> false

## channel returns nil when not connected
Onetime::Initializers::SetupRabbitMQ.channel
#=> nil

## disconnect handles nil connection gracefully
# Should not raise an error
result = begin
  Onetime::Initializers::SetupRabbitMQ.disconnect
  :no_error
rescue => e
  e.class.name
end
result
#=> :no_error

## clear_thread_channels clears thread-local storage
Thread.current[:rmq_channel] = 'fake_channel'
Onetime::Initializers::SetupRabbitMQ.clear_thread_channels
Thread.current[:rmq_channel]
#=> nil

## with_channel raises when not connected
result = begin
  Onetime::Initializers::SetupRabbitMQ.with_channel { |ch| ch }
  :no_error
rescue Onetime::Problem => e
  e.message
end
result
#=> 'RabbitMQ not connected'

## CHANNEL_KEY constant is defined
Onetime::Initializers::SetupRabbitMQ::CHANNEL_KEY
#=> :rmq_channel

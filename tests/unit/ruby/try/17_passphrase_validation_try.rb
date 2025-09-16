#!/usr/bin/env ruby

require_relative 'test_helpers'

# Load configuration for testing
OT.boot! :test, false

## Test passphrase validation when not required
# Create a mock secret action for testing
class TestSecretAction < V2::Logic::Secrets::BaseSecretAction
  def initialize(params = {})
    @params = params
    @payload = params[:secret] || {}
    @passphrase = @payload[:passphrase] || ''
  end

  def process_secret
    @kind = :test
    @secret_value = 'test'
  end

  def cust
    V2::Customer.anonymous
  end

  def plan
    V2::Customer.anonymous.plan
  end

  # Override config for testing
  def self.test_with_config(passphrase_config)
    original_config = OT.conf.dig(:site, :secret_options, :passphrase)
    OT.conf[:site][:secret_options][:passphrase] = passphrase_config
    yield
  ensure
    OT.conf[:site][:secret_options][:passphrase] = original_config
  end
end

## Test validation with no passphrase required and none provided
TestSecretAction.test_with_config({ required: false }) do
  action = TestSecretAction.new(secret: { passphrase: '' })
  begin
    action.send(:validate_passphrase)
    true
  rescue => e
    false
  end
end
#=> true

## Test validation with passphrase required but none provided
TestSecretAction.test_with_config({ required: true }) do
  action = TestSecretAction.new(secret: { passphrase: '' })
  begin
    action.send(:validate_passphrase)
    false
  rescue => e
    e.message.include?('required')
  end
end
#=> true

## Test validation with minimum length requirement
TestSecretAction.test_with_config({ required: false, minimum_length: 10 }) do
  action = TestSecretAction.new(secret: { passphrase: 'short' })
  begin
    action.send(:validate_passphrase)
    false
  rescue => e
    e.message.include?('at least 10 characters')
  end
end
#=> true

## Test validation with valid passphrase meeting minimum length
TestSecretAction.test_with_config({ required: false, minimum_length: 8 }) do
  action = TestSecretAction.new(secret: { passphrase: 'longenough' })
  begin
    action.send(:validate_passphrase)
    true
  rescue => e
    false
  end
end
#=> true

## Test validation with complexity enforcement
TestSecretAction.test_with_config({ required: false, enforce_complexity: true }) do
  action = TestSecretAction.new(secret: { passphrase: 'simplepassword' })
  begin
    action.send(:validate_passphrase)
    false
  rescue => e
    e.message.include?('uppercase')
  end
end
#=> true

## Test validation with complex passphrase meeting all requirements
TestSecretAction.test_with_config({ required: false, enforce_complexity: true }) do
  action = TestSecretAction.new(secret: { passphrase: 'Complex123!' })
  begin
    action.send(:validate_passphrase)
    true
  rescue => e
    false
  end
end
#=> true

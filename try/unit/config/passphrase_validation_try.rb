#!/usr/bin/env ruby
#
# frozen_string_literal: true

require_relative '../../support/test_logic'

# Load configuration for testing
OT.boot! :test, false

## Test passphrase validation when not required
# Create a mock secret action for testing
class TestSecretAction < V2::Logic::Secrets::BaseSecretAction
  attr_accessor :test_passphrase_config

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
    Onetime::Customer.anonymous
  end

  def plan
    Onetime::Customer.anonymous.plan
  end

  # Override the validate_passphrase method to use test config
  def validate_passphrase
    # Use test config if set, otherwise fall back to original
    passphrase_config = if @test_passphrase_config
      @test_passphrase_config
    else
      OT.conf.dig('site', 'secret_options', 'passphrase') || {}
    end

    # Check if passphrase is required
    if passphrase_config['required'] && passphrase.to_s.empty?
      raise_form_error "A passphrase is required for all secrets"
    end

    # Skip further validation if no passphrase provided
    return if passphrase.to_s.empty?

    # Validate minimum length
    min_length = passphrase_config['minimum_length'] || nil
    if min_length && passphrase.length < min_length
      raise_form_error "Passphrase must be at least #{min_length} characters long"
    end

    # Validate maximum length
    max_length = passphrase_config['maximum_length'] || nil
    if max_length && passphrase.length > max_length
      raise_form_error "Passphrase must be no more than #{max_length} characters long"
    end

    # Validate complexity if required
    if passphrase_config['enforce_complexity']
      validate_passphrase_complexity
    end
  end

  # Helper method for testing with specific config
  def self.test_with_config(passphrase_config)
    action = yield
    if action.is_a?(TestSecretAction)
      action.test_passphrase_config = passphrase_config
    end
    action
  end
end

## Test validation with no passphrase required and none provided
action = TestSecretAction.new(secret: { passphrase: '' })
action.test_passphrase_config = { 'required' => false }
begin
  action.send(:validate_passphrase)
  true
rescue => e
  false
end
#=> true

## Test validation with passphrase required but none provided
action = TestSecretAction.new(secret: { passphrase: '' })
action.test_passphrase_config = { 'required' => true }
begin
  action.send(:validate_passphrase)
  false
rescue => e
  e.message.include?('required')
end
#=> true

## Test validation with minimum length requirement
action = TestSecretAction.new(secret: { passphrase: 'short' })
action.test_passphrase_config = { 'required' => false, 'minimum_length' => 10 }
begin
  action.send(:validate_passphrase)
  false
rescue => e
  e.message.include?('at least 10 characters')
end
#=> true

## Test validation with valid passphrase meeting minimum length
action = TestSecretAction.new(secret: { passphrase: 'longenough' })
action.test_passphrase_config = { 'required' => false, 'minimum_length' => 8 }
begin
  action.send(:validate_passphrase)
  true
rescue => e
  false
end
#=> true

## Test validation with complexity enforcement
action = TestSecretAction.new(secret: { passphrase: 'simplepassword' })
action.test_passphrase_config = { 'required' => false, 'enforce_complexity' => true }
begin
  action.send(:validate_passphrase)
  false
rescue => e
  e.message.include?('uppercase')
end
#=> true

## Test validation with complex passphrase meeting all requirements
action = TestSecretAction.new(secret: { passphrase: 'Complex123!' })
action.test_passphrase_config = { 'required' => false, 'enforce_complexity' => true }
begin
  action.send(:validate_passphrase)
  true
rescue => e
  false
end
#=> true

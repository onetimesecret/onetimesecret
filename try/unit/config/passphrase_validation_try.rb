# try/unit/config/passphrase_validation_try.rb
#
# frozen_string_literal: true

require_relative '../../support/test_logic'

# Load configuration for testing
OT.boot! :test, false

@saved_passphrase_config = OT.conf.get('site.secret_options.passphrase').dup

## passphrase validation when not required
# Create a mock secret action for testing
class TestSecretAction < V2::Logic::Secrets::BaseSecretAction
  # Every key the defaults file sets under site.secret_options.passphrase,
  # unset, so a test config names only the keys it is about.
  UNSET_PASSPHRASE_CONFIG = {
    'required' => false,
    'minimum_length' => nil,
    'maximum_length' => nil,
    'enforce_complexity' => false,
  }.freeze

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
    nil # Anonymous users have nil cust
  end

  def plan
    nil # Anonymous users have nil plan
  end

  # Installs site.secret_options.passphrase for the real validate_passphrase.
  def test_passphrase_config=(passphrase_config)
    OT.conf.get('site.secret_options')['passphrase'] = UNSET_PASSPHRASE_CONFIG.merge(passphrase_config)
  end
end

## validation with no passphrase required and none provided
action = TestSecretAction.new(secret: { passphrase: '' })
action.test_passphrase_config = { 'required' => false }
begin
  action.send(:validate_passphrase)
  true
rescue => e
  false
end
#=> true

## validation with passphrase required but none provided
action = TestSecretAction.new(secret: { passphrase: '' })
action.test_passphrase_config = { 'required' => true }
begin
  action.send(:validate_passphrase)
  false
rescue => e
  e.message.include?('required')
end
#=> true

## validation with minimum length requirement
action = TestSecretAction.new(secret: { passphrase: 'short' })
action.test_passphrase_config = { 'required' => false, 'minimum_length' => 10 }
begin
  action.send(:validate_passphrase)
  false
rescue => e
  e.message.include?('at least 10 characters')
end
#=> true

## validation with valid passphrase meeting minimum length
action = TestSecretAction.new(secret: { passphrase: 'longenough' })
action.test_passphrase_config = { 'required' => false, 'minimum_length' => 8 }
begin
  action.send(:validate_passphrase)
  true
rescue => e
  false
end
#=> true

## validation with complexity enforcement
action = TestSecretAction.new(secret: { passphrase: 'simplepassword' })
action.test_passphrase_config = { 'required' => false, 'enforce_complexity' => true }
begin
  action.send(:validate_passphrase)
  false
rescue => e
  e.message.include?('uppercase')
end
#=> true

## validation with complex passphrase meeting all requirements
action = TestSecretAction.new(secret: { passphrase: 'Complex123!' })
action.test_passphrase_config = { 'required' => false, 'enforce_complexity' => true }
begin
  action.send(:validate_passphrase)
  true
rescue => e
  false
end
#=> true

# Teardown
OT.conf.get('site.secret_options')['passphrase'] = @saved_passphrase_config

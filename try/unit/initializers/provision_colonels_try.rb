# try/unit/initializers/provision_colonels_try.rb
#
# frozen_string_literal: true

require_relative '../../support/test_helpers'

# Load the app properly
OT.boot! :test, false

# Load the initializer under test
require_relative '../../../lib/onetime/initializers/provision_colonels'

# Setup section

# Mock config for testing
def setup_test_config(auth_enabled: true, colonels: [], auth_mode: 'simple')
  # Create a minimal config
  config = {
    'site' => {
      'host' => 'localhost',
      'domain' => 'localhost',
      'ssl' => false,
      'secret' => SecureRandom.hex(32),
      'authentication' => {
        'enabled' => auth_enabled,
        'colonels' => colonels,
      },
    },
    'redis' => {
      'uri' => Familia.uri.to_s,
    },
  }

  # Store in OT singleton
  OT.instance_variable_set(:@conf, config)

  # Mock auth_config
  auth_config_mock = Object.new
  auth_config_mock.define_singleton_method(:mode) { auth_mode }
  auth_config_mock.define_singleton_method(:full_enabled?) { auth_mode == 'full' }
  auth_config_mock.define_singleton_method(:simple_enabled?) { auth_mode == 'simple' }

  Onetime.define_singleton_method(:auth_config) { auth_config_mock }

  config
end

# Cleanup helper
def cleanup_test_customer(email)
  return unless Onetime::Customer.email_exists?(email)

  cust = Onetime::Customer.find_by_email(email)
  # Remove from unique index
  Onetime::Customer.email_index.delete!
  # Remove from instances sorted set
  Onetime::Customer.instances.remove(cust.objid)
  # Clear all hash fields
  cust.clear
end

## Skips when authentication is disabled
setup_test_config(auth_enabled: false, colonels: ['test@example.com'])
init = Onetime::Initializers::ProvisionColonels.new
result = init.execute({})
result.nil?
#=> true

## Skips when colonels list is empty
setup_test_config(auth_enabled: true, colonels: [])
init = Onetime::Initializers::ProvisionColonels.new
result = init.execute({})
result.nil?
#=> true

## Skips when colonels contains only CHANGEME
setup_test_config(auth_enabled: true, colonels: ['CHANGEME@example.com'])
init = Onetime::Initializers::ProvisionColonels.new
result = init.execute({})
result.nil?
#=> true

## Creates new colonel in simple mode
cleanup_test_customer('colonel1@test.local')
setup_test_config(auth_enabled: true, colonels: ['colonel1@test.local'], auth_mode: 'simple')
init = Onetime::Initializers::ProvisionColonels.new
init.execute({})
cust = Onetime::Customer.find_by_email('colonel1@test.local')
result = [cust.role, cust.verified]
cleanup_test_customer('colonel1@test.local')
result
#=> ['colonel', 'true']

## Sets verified_by field on new accounts
cleanup_test_customer('colonel2@test.local')
setup_test_config(auth_enabled: true, colonels: ['colonel2@test.local'], auth_mode: 'simple')
init = Onetime::Initializers::ProvisionColonels.new
init.execute({})
cust = Onetime::Customer.find_by_email('colonel2@test.local')
result = cust.verified_by
cleanup_test_customer('colonel2@test.local')
result
#=> 'auto_provision'

## Skips existing colonel with correct role
cleanup_test_customer('colonel3@test.local')
# Create existing colonel
existing = Onetime::Customer.create!(
  email: 'colonel3@test.local',
  role: 'colonel',
  verified: 'true',
)
setup_test_config(auth_enabled: true, colonels: ['colonel3@test.local'], auth_mode: 'simple')
init = Onetime::Initializers::ProvisionColonels.new
init.execute({})
# Should not have changed
cust = Onetime::Customer.find_by_email('colonel3@test.local')
result = [cust.role, cust.objid == existing.objid]
cleanup_test_customer('colonel3@test.local')
result
#=> ['colonel', true]

## Handles multiple colonels
cleanup_test_customer('multi1@test.local')
cleanup_test_customer('multi2@test.local')
setup_test_config(
  auth_enabled: true,
  colonels: ['multi1@test.local', 'multi2@test.local'],
  auth_mode: 'simple',
)
init = Onetime::Initializers::ProvisionColonels.new
init.execute({})
cust1 = Onetime::Customer.find_by_email('multi1@test.local')
cust2 = Onetime::Customer.find_by_email('multi2@test.local')
result = [cust1.role, cust2.role]
cleanup_test_customer('multi1@test.local')
cleanup_test_customer('multi2@test.local')
result
#=> ['colonel', 'colonel']

## Password is set with argon2
cleanup_test_customer('pw@test.local')
setup_test_config(auth_enabled: true, colonels: ['pw@test.local'], auth_mode: 'simple')
init = Onetime::Initializers::ProvisionColonels.new
init.execute({})
cust = Onetime::Customer.find_by_email('pw@test.local')
# Check passphrase_encryption field is set to '2' (argon2)
result = cust.passphrase_encryption
cleanup_test_customer('pw@test.local')
result
#=> '2'

## Passphrase hash is not empty
cleanup_test_customer('hash@test.local')
setup_test_config(auth_enabled: true, colonels: ['hash@test.local'], auth_mode: 'simple')
init = Onetime::Initializers::ProvisionColonels.new
init.execute({})
cust = Onetime::Customer.find_by_email('hash@test.local')
result = !cust.passphrase.to_s.empty?
cleanup_test_customer('hash@test.local')
result
#=> true

## Does not fail boot on individual errors
cleanup_test_customer('error@test.local')
setup_test_config(auth_enabled: true, colonels: ['error@test.local', 'valid@test.local'], auth_mode: 'simple')

# Mock Customer.create! to fail for first email
original_create = Onetime::Customer.singleton_method(:create!)
failure_count = 0
Onetime::Customer.define_singleton_method(:create!) do |**kwargs|
  if kwargs[:email] == 'error@test.local' && failure_count == 0
    failure_count += 1
    raise StandardError, 'Simulated error'
  end
  original_create.call(**kwargs)
end

init = Onetime::Initializers::ProvisionColonels.new
# Should not raise, just log
init.execute({})

# Restore original method
Onetime::Customer.define_singleton_method(:create!, &original_create)

# Second colonel should have been created
result = Onetime::Customer.email_exists?('valid@test.local')
cleanup_test_customer('valid@test.local')
result
#=> true

## Filters out example.com domains
setup_test_config(auth_enabled: true, colonels: ['admin@example.com'])
init = Onetime::Initializers::ProvisionColonels.new
result = init.execute({})
result.nil?
#=> true

## Handles colonels array containing false
setup_test_config(auth_enabled: true, colonels: [false])
init = Onetime::Initializers::ProvisionColonels.new
result = init.execute({})
result.nil?
#=> true

## Warns about existing customer with wrong role
cleanup_test_customer('wrongrole@test.local')
# Create existing customer with regular role
existing = Onetime::Customer.create!(
  email: 'wrongrole@test.local',
  role: 'customer',
  verified: 'true',
)
setup_test_config(auth_enabled: true, colonels: ['wrongrole@test.local'], auth_mode: 'simple')
init = Onetime::Initializers::ProvisionColonels.new
init.execute({})
# Role should remain unchanged (requires manual fix)
cust = Onetime::Customer.find_by_email('wrongrole@test.local')
result = cust.role
cleanup_test_customer('wrongrole@test.local')
result
#=> 'customer'

## Generated password has correct length
cleanup_test_customer('pwlen@test.local')
setup_test_config(auth_enabled: true, colonels: ['pwlen@test.local'], auth_mode: 'simple')
init = Onetime::Initializers::ProvisionColonels.new
# Capture generated password via log
captured_password = nil
original_log = init.method(:log_password)
init.define_singleton_method(:log_password) do |email, password|
  captured_password = password
  original_log.call(email, password)
end
init.execute({})
result = captured_password&.length
cleanup_test_customer('pwlen@test.local')
result
#=> 20

## Generated password is alphanumeric only
cleanup_test_customer('pwformat@test.local')
setup_test_config(auth_enabled: true, colonels: ['pwformat@test.local'], auth_mode: 'simple')
init = Onetime::Initializers::ProvisionColonels.new
# Capture generated password
captured_password = nil
original_log = init.method(:log_password)
init.define_singleton_method(:log_password) do |email, password|
  captured_password = password
  original_log.call(email, password)
end
init.execute({})
result = captured_password&.match?(/\A[A-Za-z0-9]+\z/)
cleanup_test_customer('pwformat@test.local')
result
#=> true

## Can verify password after creation
cleanup_test_customer('verify@test.local')
setup_test_config(auth_enabled: true, colonels: ['verify@test.local'], auth_mode: 'simple')
init = Onetime::Initializers::ProvisionColonels.new
# Capture generated password
captured_password = nil
original_log = init.method(:log_password)
init.define_singleton_method(:log_password) do |email, password|
  captured_password = password
  original_log.call(email, password)
end
init.execute({})
cust = Onetime::Customer.find_by_email('verify@test.local')
# Verify the password works
result = cust.passphrase?(captured_password)
cleanup_test_customer('verify@test.local')
result
#=> true

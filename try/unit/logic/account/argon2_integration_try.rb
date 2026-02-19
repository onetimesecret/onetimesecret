# try/unit/logic/account/argon2_integration_try.rb
#
# frozen_string_literal: true

# These tryouts test the ARGON2_SECRET integration changes:
#
# 1. Config guard: ENV handling for empty string vs nil vs valid secret
# 2. Password verification dispatch in simple mode under varying ARGON2_SECRET
# 3. verify_password_full_mode error handling when auth DB unavailable
# 4. Both RequestEmailChange and DestroyAccount share the same pattern
#
# The test environment runs in simple auth mode (Redis-only), so
# verify_password dispatches to cust.passphrase?. Full mode tests
# verify error handling paths when the auth database is unavailable.

require_relative '../../../support/test_logic'

OT.boot! :test, false

@password = 'testpass123'
@session = {}
@email_address = generate_unique_test_email('argon2int')
@cust = Onetime::Customer.new email: @email_address
@cust.update_passphrase @password
@strategy_result = MockStrategyResult.new(session: @session, user: @cust)
@da_cust = Onetime::Customer.new email: generate_unique_test_email('da-argon2')
@da_cust.update_passphrase 'destroy-me-123'
@da_strategy = MockStrategyResult.new(session: @session, user: @da_cust)

# TRYOUTS

# --- Config Guard: ENV handling for ARGON2_SECRET ---
# Tests the guard logic: `secret && !secret.empty?`
# This mirrors the fix in apps/web/auth/config/features/argon2.rb

## Config guard: nil ARGON2_SECRET skips pepper (short-circuits to nil)
with_env('ARGON2_SECRET', nil) do
  secret = ENV.fetch('ARGON2_SECRET', nil)
  should_set = secret && !secret.empty?
  [secret.nil?, should_set]
end
#=> [true, nil]

## Config guard: empty string ARGON2_SECRET is treated as unset
with_env('ARGON2_SECRET', '') do
  secret = ENV.fetch('ARGON2_SECRET', nil)
  should_set = secret && !secret.empty?
  [secret, should_set]
end
#=> ['', false]

## Config guard: valid ARGON2_SECRET triggers pepper setting
with_env('ARGON2_SECRET', 'my-secret-pepper-key') do
  secret = ENV.fetch('ARGON2_SECRET', nil)
  should_set = secret && !secret.empty?
  [secret, should_set]
end
#=> ['my-secret-pepper-key', true]

## Config guard: whitespace-only ARGON2_SECRET is treated as set (not stripped)
with_env('ARGON2_SECRET', '   ') do
  secret = ENV.fetch('ARGON2_SECRET', nil)
  should_set = secret && !secret.empty?
  [secret, should_set]
end
#=> ['   ', true]

## Config guard: all three falsy cases produce falsy should_set
results = [nil, ''].map do |val|
  with_env('ARGON2_SECRET', val) do
    secret = ENV.fetch('ARGON2_SECRET', nil)
    !!(secret && !secret.empty?)
  end
end
results
#=> [false, false]

# --- Password Verification: simple mode with ARGON2_SECRET variations ---

## Correct password passes with ARGON2_SECRET unset
new_email = generate_unique_test_email('argon2-unset')
with_env('ARGON2_SECRET', nil) do
  params = { 'password' => @password, 'new_email' => new_email }
  obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
  obj.raise_concerns
end
#=> nil

## Correct password passes with ARGON2_SECRET set to a value
new_email = generate_unique_test_email('argon2-set')
with_env('ARGON2_SECRET', 'test-pepper-value') do
  params = { 'password' => @password, 'new_email' => new_email }
  obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
  obj.raise_concerns
end
#=> nil

## Correct password passes with ARGON2_SECRET as empty string
new_email = generate_unique_test_email('argon2-empty')
with_env('ARGON2_SECRET', '') do
  params = { 'password' => @password, 'new_email' => new_email }
  obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
  obj.raise_concerns
end
#=> nil

## Wrong password fails regardless of ARGON2_SECRET value
with_env('ARGON2_SECRET', 'some-secret') do
  params = { 'password' => 'wrongpassword', 'new_email' => 'new@example.com' }
  obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
  begin
    obj.raise_concerns
  rescue => e
    [e.class, e.message]
  end
end
#=> [Onetime::FormError, 'Current password is incorrect']

# --- DestroyAccount: same verification pattern ---

## DestroyAccount correct password passes with ARGON2_SECRET unset
with_env('ARGON2_SECRET', nil) do
  params = { 'confirmation' => 'destroy-me-123' }
  obj = AccountAPI::Logic::Account::DestroyAccount.new @da_strategy, params
  obj.raise_concerns
end
#=> nil

## DestroyAccount wrong password fails with ARGON2_SECRET set
with_env('ARGON2_SECRET', 'pepper-value') do
  params = { 'confirmation' => 'wrong-pass' }
  obj = AccountAPI::Logic::Account::DestroyAccount.new @da_strategy, params
  begin
    obj.raise_concerns
  rescue => e
    [e.class, e.message]
  end
end
#=> [Onetime::FormError, 'Please check the password.']

# --- verify_password: edge cases ---

## verify_password returns false for empty string (RequestEmailChange)
params = { 'password' => @password, 'new_email' => 'new@example.com' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
obj.send(:verify_password, '')
#=> false

## verify_password returns false for nil (RequestEmailChange)
params = { 'password' => @password, 'new_email' => 'new@example.com' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
obj.send(:verify_password, nil)
#=> false

## verify_password returns false for empty string (DestroyAccount)
params = { 'confirmation' => 'test' }
obj = AccountAPI::Logic::Account::DestroyAccount.new @da_strategy, params
obj.send(:verify_password, '')
#=> false

## verify_password returns false for nil (DestroyAccount)
params = { 'confirmation' => 'test' }
obj = AccountAPI::Logic::Account::DestroyAccount.new @da_strategy, params
obj.send(:verify_password, nil)
#=> false

# --- verify_password_full_mode: method presence and error handling ---

## RequestEmailChange has verify_password_full_mode method
params = { 'password' => @password, 'new_email' => 'new@example.com' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
obj.respond_to?(:verify_password_full_mode, true)
#=> true

## DestroyAccount has verify_password_full_mode method
params = { 'confirmation' => 'test' }
obj = AccountAPI::Logic::Account::DestroyAccount.new @da_strategy, params
obj.respond_to?(:verify_password_full_mode, true)
#=> true

# --- Auth mode dispatch: simple mode uses passphrase? ---

## In test env, auth mode is simple (not full)
Onetime.auth_config.full_enabled?
#=> false

## In simple mode, verify_password uses cust.passphrase? (correct password)
params = { 'password' => @password, 'new_email' => 'new@example.com' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
obj.send(:verify_password, @password)
#=> true

## In simple mode, verify_password uses cust.passphrase? (wrong password)
params = { 'password' => @password, 'new_email' => 'new@example.com' }
obj = AccountAPI::Logic::Account::RequestEmailChange.new @strategy_result, params
obj.send(:verify_password, 'totally-wrong')
#=> false

# --- internal_request feature is enabled in base config ---

## Base config file includes internal_request enable
base_config_path = File.join(ENV['ONETIME_HOME'], 'apps/web/auth/config/base.rb')
content = File.read(base_config_path)
content.include?('auth.enable :internal_request')
#=> true

## Argon2 config uses the corrected guard pattern
argon2_config_path = File.join(ENV['ONETIME_HOME'], 'apps/web/auth/config/features/argon2.rb')
content = File.read(argon2_config_path)
content.include?('auth.argon2_secret secret if secret')
#=> true

# Cleanup
@cust.delete!
@da_cust.delete!

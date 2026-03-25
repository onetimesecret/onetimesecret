# try/unit/logic/account/update_password_try.rb
#
# frozen_string_literal: true

# Tests for UpdatePassword logic in simple auth mode (Redis passphrase).
# Covers password validation, verification, and the change flow.

require_relative '../../../support/test_logic'

OT.boot! :test, false

@email_address = generate_random_email
@current_password = 'oldp4ssw0rd'
@new_password = 'n3wP4ssw0rd'
@session = {}
@cust = Onetime::Customer.new email: @email_address
@cust.update_passphrase @current_password
@strategy_result = MockStrategyResult.new(session: @session, user: @cust)

# TRYOUTS

## Can create UpdatePassword instance
params = {
  'password' => @current_password,
  'newpassword' => @new_password,
  'password-confirm' => @new_password
}
obj = AccountAPI::Logic::Account::UpdatePassword.new @strategy_result, params
obj.class.name
#=> 'AccountAPI::Logic::Account::UpdatePassword'

## Raises error when current password is empty
params = { 'password' => '', 'newpassword' => @new_password, 'password-confirm' => @new_password }
obj = AccountAPI::Logic::Account::UpdatePassword.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Current password is required']

## Raises error when current password is incorrect
params = { 'password' => 'wrongpassword', 'newpassword' => @new_password, 'password-confirm' => @new_password }
obj = AccountAPI::Logic::Account::UpdatePassword.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Current password is incorrect']

## Raises error when new password matches current
params = { 'password' => @current_password, 'newpassword' => @current_password, 'password-confirm' => @current_password }
obj = AccountAPI::Logic::Account::UpdatePassword.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'New password cannot be the same as current password']

## Raises error when new password is too short
params = { 'password' => @current_password, 'newpassword' => 'ab', 'password-confirm' => 'ab' }
obj = AccountAPI::Logic::Account::UpdatePassword.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'New password is too short']

## Raises error when password confirmation does not match
params = { 'password' => @current_password, 'newpassword' => @new_password, 'password-confirm' => 'mismatch' }
obj = AccountAPI::Logic::Account::UpdatePassword.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'New passwords do not match']

## No errors raised with valid params
cust = Onetime::Customer.new email: generate_random_email
cust.update_passphrase @current_password
strategy_result = MockStrategyResult.new(session: @session, user: cust)
params = { 'password' => @current_password, 'newpassword' => @new_password, 'password-confirm' => @new_password }
obj = AccountAPI::Logic::Account::UpdatePassword.new strategy_result, params
obj.raise_concerns
#=> nil

## Process changes the password successfully
@change_cust = Onetime::Customer.new email: generate_random_email
@change_cust.update_passphrase @current_password
strategy_result = MockStrategyResult.new(session: @session, user: @change_cust)
params = { 'password' => @current_password, 'newpassword' => @new_password, 'password-confirm' => @new_password }
obj = AccountAPI::Logic::Account::UpdatePassword.new strategy_result, params
obj.raise_concerns
obj.process
@change_cust.passphrase?(@new_password)
#=> true

## Old password no longer works after change
@change_cust.passphrase?(@current_password)
#=> false

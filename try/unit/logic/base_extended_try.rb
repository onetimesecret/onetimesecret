# try/unit/logic/base_extended_try.rb
#
# frozen_string_literal: true

# These tryouts test the base logic of the Onetime application,
# specifically focusing on the CreateAccount functionality.
#
# We're testing various aspects of the CreateAccount logic, including:
# 1. Instance creation
# 2. Email validation
#
# These tests aim to ensure that the basic account creation logic
# in the Onetime application works correctly, which is crucial for
# user onboarding and management.
#
# The tryouts simulate different scenarios of using the CreateAccount
# logic without needing to run the full application, allowing for
# targeted testing of this specific functionality.

require 'securerandom'

require_relative '../../support/test_logic'

# Load the app
OT.boot! :test, false

# Setup some variables for these tryouts
@now = Familia.now
@from_address = OT.conf.dig('emailer', 'from')
@email_address = generate_unique_test_email("base_extended")
@session = {}
@strategy_result = MockStrategyResult.new(session: @session, user: nil)
@cust = Customer.new email: @email_address
@params = {}
@locale = 'en'
@obj = AccountAPI::Logic::Account::CreateAccount.new @strategy_result, {}

# A generator for valid params for creating an account
@valid_params = lambda do
  entropy = SecureRandom.hex[0..6]
  email = "tryouts+60+#{entropy}@onetimesecret.com"
  pword = 'loopersucks'
  {
    'planid' => :individual_v1,
    'login' => email,
    'password' => pword,
    'password2' => pword,

    # This is a hidden field, so it should be empty. If it has a value, it's
    'skill' => '',
  }
end


# TRYOUTS

## Can create CreateAccount instance
@obj.class
#=> AccountAPI::Logic::Account::CreateAccount

## Knows an invalid address
@obj.valid_email?('bogusjourney')
#=> false

## Knows a valid email address
@obj.valid_email?(@email_address)
#=> true

## Can't tell the diff between a valid email syntax and a deliverable
## email address. The default from address is changeme@example.com so
## @ it's a valid email string but not an actual, real mailbox.
## This is b/c currently we only perform regex validation.
@obj.valid_email?(@from_address)
#=> true

## Can create account and it's not verified by default.
sess = {}
strategy_result = MockStrategyResult.new(session: sess, user: nil)
logic = AccountAPI::Logic::Account::CreateAccount.new strategy_result, @valid_params.call, 'en'
logic.raise_concerns
logic.process
[logic.autoverify.to_s, logic.cust.verified.to_s, OT.conf.dig('site', 'authentication', 'autoverify').to_s]
#=> ['false', 'false', 'false']

## Can create account and have it auto-verified.
sess = {}
strategy_result = MockStrategyResult.new(session: sess, user: nil)
old_conf = OT.instance_variable_get(:@conf)
new_conf = {
  'site' => {
    'authentication' => {
      'autoverify' => true, # force the config to be true
    },
  },
}
OT.instance_variable_set(:@conf, new_conf)
logic = AccountAPI::Logic::Account::CreateAccount.new strategy_result, @valid_params.call, 'en'
logic.raise_concerns
logic.process
ret = [logic.autoverify.to_s, logic.cust.verified.to_s, OT.conf.dig('site', 'authentication', 'autoverify').to_s]
OT.instance_variable_set(:@conf, old_conf)
ret
#=> ['true', 'true', 'true']

## send_verification_email returns false when mail delivery fails (DX-6)
sess = {}
strategy_result = MockStrategyResult.new(session: sess, user: nil)
logic = AccountAPI::Logic::Account::CreateAccount.new strategy_result, @valid_params.call, 'en'
logic.raise_concerns
logic.process
original_deliver = Onetime::Mail::Mailer.method(:deliver)
Onetime::Mail::Mailer.define_singleton_method(:deliver) do |*_args, **_kwargs|
  raise StandardError, 'SMTP unreachable (tryout stub)'
end
ret = logic.send(:send_verification_email, customer: logic.cust)
Onetime::Mail::Mailer.define_singleton_method(:deliver, original_deliver)
ret
#=> false

## send_verification_email returns true when mail delivery succeeds (DX-6)
sess = {}
strategy_result = MockStrategyResult.new(session: sess, user: nil)
logic = AccountAPI::Logic::Account::CreateAccount.new strategy_result, @valid_params.call, 'en'
logic.raise_concerns
logic.process
original_deliver = Onetime::Mail::Mailer.method(:deliver)
Onetime::Mail::Mailer.define_singleton_method(:deliver) do |*_args, **_kwargs|
  :delivered
end
ret = logic.send(:send_verification_email, customer: logic.cust)
Onetime::Mail::Mailer.define_singleton_method(:deliver, original_deliver)
ret
#=> true

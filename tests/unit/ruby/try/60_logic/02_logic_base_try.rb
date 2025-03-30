# tests/unit/ruby/try/60_logic/02_logic_base_try.rb

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

require_relative '../test_logic'

# Load the app
OT.boot! :test, false

# Setup some variables for these tryouts
@now = DateTime.now
@from_address = OT.conf.dig(:emailer, :from)
@email_address = 'tryouts@onetimesecret.com'
@sess = Session.new '255.255.255.255', 'anon'
@cust = Customer.new @email_address
@sess.event_clear! :send_feedback
@params = {}
@locale = 'en'
@obj = V2::Logic::Account::CreateAccount.new @sess, @cust

# A generator for valid params for creating an account
@valid_params = lambda do
  entropy = OT.entropy[0..6]
  email = "tryouts+60+#{entropy}@onetimesecret.com"
  pword = 'loopersucks'
  {
    planid: :individual_v1,
    u: email,
    p: pword,
    p2: pword,

    # This is a hidden field, so it should be empty. If it has a value, it's
    skill: '',
  }
end


# TRYOUTS

## Can create CreateAccount instance
@obj.class
#=> V2::Logic::Account::CreateAccount

## Knows an invalid address
@obj.valid_email?('bogusjourney')
#=> false

## Knows a valid email address
@obj.valid_email?(@email_address)
#=> true

## Can't tell the diff between a valid email syntax and a deliverable
## email address. The default from address is changeme@example.com so
## @ it's a valid email string but not an actual, real mailbox.
##
## This is b/c currently we only perform regex validation.
##
@obj.valid_email?(@from_address)
#=> true

## Can create account and it's not verified by default.
sess = Session.create '255.255.255.255', 'anon'
cust = Customer.new
logic = V2::Logic::Account::CreateAccount.new sess, cust, @valid_params.call, 'en'
logic.raise_concerns
logic.process
[logic.autoverify, logic.cust.verified, OT.conf.dig(:site, :authentication, :autoverify)]
#=> [false, 'false', false]

## Can create account and have it auto-verified.
sess = Session.create '255.255.255.255', 'anon'
cust = Customer.new
OT.conf[:site][:authentication][:autoverify] = true # force the config to be true
logic = V2::Logic::Account::CreateAccount.new sess, cust, @valid_params.call, 'en'
logic.raise_concerns
logic.process
[logic.autoverify, logic.cust.verified, OT.conf.dig(:site, :authentication, :autoverify)]
#=> [true, 'true', true]

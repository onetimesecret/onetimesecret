# frozen_string_literal: true

# These tryouts test the account destruction functionality in the OneTime application.
# They cover various aspects of the account destruction process, including:
#
# 1. Validating user input for account destruction
# 2. Handling password confirmation
# 3. Rate limiting destruction attempts
# 4. Processing account destruction
# 5. Verifying the state of destroyed accounts
#
# These tests aim to ensure that the account destruction process is secure, properly validated,
# and correctly updates the user's account state.
#
# The tryouts use the OT::Logic::Account::DestroyAccount class to simulate different account destruction
# scenarios, allowing for targeted testing of this critical functionality without affecting real user accounts.

require_relative '../lib/onetime'

# Load the app
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test.yaml')
OT.boot! :app

# Setup some variables for these tryouts
@email_address = 'changeme@example.com'
@now = DateTime.now
@sess = OT::Session.new '255.255.255.255', 'anon'
@sess.event_clear! :destroy_account
@cust = OT::Customer.new @email_address
@sess.event_clear! :send_feedback
@params = {
  confirmation: 'pa55w0rd'
}

def generate_random_email
  # Generate a random username
  username = (0...8).map { ('a'..'z').to_a[rand(26)] }.join
  # Define a domain
  domain = "onetimesecret.com"
  # Combine to form an email address
  "#{username}@#{domain}"
end

# TRYOUTS

## Can create DestroyAccount instance
obj = OT::Logic::Account::DestroyAccount.new @sess, @cust, @params
obj.params[:confirmation]
#=> @params[:confirmation]

## Processing params removes leading and trailing whitespace
## from current password, but not in the middle.
password_guess = '   padded p455   '
obj = OT::Logic::Account::DestroyAccount.new @sess, @cust, confirmation: password_guess
obj.process_params
#=> 'padded p455'


## Raises an error if no params are passed at all
obj = OT::Logic::Account::DestroyAccount.new @sess, @cust
begin
  obj.raise_concerns
rescue => e
  puts e.backtrace
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Please check the password.']


## Raises an error if the current password is nil
obj = OT::Logic::Account::DestroyAccount.new @sess, @cust, confirmation: nil
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Password confirmation is required.']


## Raises an error if the current password is empty
obj = OT::Logic::Account::DestroyAccount.new @sess, @cust, confirmation: ''
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Password confirmation is required.']


## Raises an error if the password is incorrect
cust = OT::Customer.new generate_random_email
obj = OT::Logic::Account::DestroyAccount.new @sess, cust, @params
cust.update_passphrase 'wrong password'
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Please check the password.']


## No errors are raised as long as the password is correct
cust = OT::Customer.new generate_random_email
password_guess = @params[:confirmation]
obj = OT::Logic::Account::DestroyAccount.new @sess, cust, @params
cust.update_passphrase password_guess # update the password to be correct
obj.raise_concerns
#=> nil


## Too many attempts is throttled by rate limiting
cust = OT::Customer.new generate_random_email
password_guess = @params[:confirmation]
obj = OT::Logic::Account::DestroyAccount.new @sess, cust, @params
cust.update_passphrase password_guess

# Make sure we start from 0
@sess.event_clear! :destroy_account

last_error = nil
6.times do
  begin
    obj.raise_concerns
  rescue => e
    last_error = [e.class, e.message]
  end
end
@sess.event_clear! :destroy_account
last_error
#=> [OT::LimitExceeded, '[limit-exceeded] 3ytjp10tjtosfj7ljcscmblz1sc6ds9 for destroy_account (6)']

## Attempt to process the request without calling raise_concerns first
password_guess = @params[:confirmation]
obj = OT::Logic::Account::DestroyAccount.new @sess, @cust, @params
begin
  obj.process
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, "We have concerns about that request."]

## Process the request and destroy the account
cust = OT::Customer.new generate_random_email
obj = OT::Logic::Account::DestroyAccount.new @sess, cust, @params
cust.update_passphrase @params[:confirmation] # set the passphrase
obj.raise_concerns
obj.process

# NOTE: When running in debug mode, we intentionally don't call
# Customer#destroy_requested! so the passphrase doesn't get
# cleared out, causing this test to fail.
# See DestroyAccount for more details.
post_destroy_passphrase = if Onetime.debug
  ''
else
  cust.passphrase
end
puts [cust.role, cust.verified, post_destroy_passphrase]
[cust.role, cust.verified, post_destroy_passphrase]
#=> ['user_deleted_self', 'false', '']

## Destroyed account gets a new api key
cust = OT::Customer.new generate_random_email
first_token = cust.regenerate_apitoken  # first we need to set an api key
obj = OT::Logic::Account::DestroyAccount.new @sess, cust, @params
cust.update_passphrase @params[:confirmation]
obj.raise_concerns
obj.process

# NOTE: See note above for `post_destroy_passphrase`
post_destroy_apitoken = if Onetime.debug
  ''
else
  cust.apitoken
end

first_token.eql?(post_destroy_apitoken)
#=> false


@sess.event_clear! :destroy_account

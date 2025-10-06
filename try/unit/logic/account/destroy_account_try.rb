# try/60_logic/24_logic_destroy_account_try.rb

# These tryouts test the account destruction functionality in the Onetime application.
# They cover various aspects of the account destruction process, including:
#
# 1. Validating user input for account destruction
# 2. Handling password confirmation
# 3. Processing account destruction
# 4. Verifying the state of destroyed accounts
#
# These tests aim to ensure that the account destruction process is secure, properly validated,
# and correctly updates the user's account state.
#
# The tryouts use the V2::Logic::Account::DestroyAccount class to simulate different account destruction
# scenarios, allowing for targeted testing of this critical functionality without affecting real user accounts.

require_relative '../../../support/test_logic'

# Load the app
OT.boot! :test, false

# Setup some variables for these tryouts
@email_address = 'changeme@example.com'
@now = DateTime.now
@sess = V2::Session.new '255.255.255.255', 'anon'
@cust = V2::Customer.new email: @email_address
@params = {
  confirmation: 'pa55w0rd'
}

# TRYOUTS

## Can create DestroyAccount instance
obj = V2::Logic::Account::DestroyAccount.new @sess, @cust, @params
obj.params[:confirmation]
#=> @params[:confirmation]

## Processing params removes leading and trailing whitespace
## from current password, but not in the middle.
password_guess = '   padded p455   '
obj = V2::Logic::Account::DestroyAccount.new @sess, @cust, confirmation: password_guess
obj.process_params
#=> 'padded p455'


## Raises an error if no params are passed at all
obj = V2::Logic::Account::DestroyAccount.new @sess, @cust
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Please check the password.']


## Raises an error if the current password is nil
obj = V2::Logic::Account::DestroyAccount.new @sess, @cust, confirmation: nil
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Password confirmation is required.']


## Raises an error if the current password is empty
obj = V2::Logic::Account::DestroyAccount.new @sess, @cust, confirmation: ''
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Password confirmation is required.']


## Raises an error if the password is incorrect
cust = V2::Customer.new email: generate_random_email
obj = V2::Logic::Account::DestroyAccount.new @sess, cust, @params
cust.update_passphrase 'wrong password'
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Please check the password.']


## No errors are raised as long as the password is correct
cust = V2::Customer.new email: generate_random_email
password_guess = @params[:confirmation]
obj = V2::Logic::Account::DestroyAccount.new @sess, cust, @params
cust.update_passphrase password_guess # update the password to be correct
obj.raise_concerns
#=> nil

## Attempt to process the request without calling raise_concerns first

password_guess = @params[:confirmation]
obj = V2::Logic::Account::DestroyAccount.new @sess, @cust, @params
begin
  obj.process
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, "We have concerns about that request."]

## Process the request and destroy the account
cust = V2::Customer.new email: generate_random_email
obj = V2::Logic::Account::DestroyAccount.new @sess, cust, @params
cust.update_passphrase @params[:confirmation] # set the passphrase
obj.raise_concerns
obj.process

# NOTE: When running in debug mode, we intentionally don't call
# V2::Customer#destroy_requested! so the passphrase doesn't get
# cleared out, causing this test to fail.
# See DestroyAccount for more details.
post_destroy_passphrase = if Onetime.debug
  ''
else
  cust.passphrase
end
[cust.role, cust.verified, post_destroy_passphrase]
#=> ['user_deleted_self', 'false', '']

## Destroyed account gets a new api key
cust = V2::Customer.new email: generate_random_email
first_token = cust.regenerate_apitoken  # first we need to set an api key
obj = V2::Logic::Account::DestroyAccount.new @sess, cust, @params
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

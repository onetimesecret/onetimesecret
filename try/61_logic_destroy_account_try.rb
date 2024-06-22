# frozen_string_literal: true

require_relative '../lib/onetime'

# Load the app
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.boot! :app

# Setup some variables for these tryouts
@email_address = 'changeme@example.com'
@now = DateTime.now
@sess = OT::Session.new
@sess.event_clear! :destroy_account
@cust = OT::Customer.new @email_address
@sess.event_clear! :send_feedback
@params = {
  currentp: 'pa55w0rd'
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
obj = OT::Logic::DestroyAccount.new @sess, @cust, @params
obj.params[:currentp]
#=> @params[:currentp]

## Processing params removes leading and trailing whitespace
## from current password, but not in the middle.
password_guess = '   padded p455   '
obj = OT::Logic::DestroyAccount.new @sess, @cust, currentp: password_guess
obj.process_params
#=> 'padded p455'


## Raises an error if no params are passed at all
obj = OT::Logic::DestroyAccount.new @sess, @cust
begin
  obj.raise_concerns
rescue => e
  puts e.backtrace
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Password does not match.']


## Raises an error if the current password is nil
obj = OT::Logic::DestroyAccount.new @sess, @cust, currentp: nil
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Password confirmation is required.']


## Raises an error if the current password is empty
obj = OT::Logic::DestroyAccount.new @sess, @cust, currentp: ''
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Password confirmation is required.']


## Raises an error if the password is incorrect
cust = OT::Customer.new generate_random_email
password_guess = 'wrong password'
obj = OT::Logic::DestroyAccount.new @sess, cust, @params
cust.update_passphrase password_guess
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Password does not match.']


## No errors are raised as long as the password is correct
cust = OT::Customer.new generate_random_email
password_guess = @params[:currentp]
obj = OT::Logic::DestroyAccount.new @sess, cust, @params
cust.update_passphrase password_guess
obj.raise_concerns
#=> nil


## Too many attempts is throttled by rate limiting
cust = OT::Customer.new generate_random_email
password_guess = @params[:currentp]
obj = OT::Logic::DestroyAccount.new @sess, cust, @params
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
#=> [OT::LimitExceeded, '[limit-exceeded] 9b8yjehe955u8l6kicd1jz90xqj8nz for destroy_account (6)']

## Attempt to process the request without calling raise_concerns first
password_guess = @params[:currentp]
obj = OT::Logic::DestroyAccount.new @sess, @cust, @params
begin
  obj.process
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, "We have concerns about that request."]

## Process the request and destroy the account
cust = OT::Customer.new generate_random_email
obj = OT::Logic::DestroyAccount.new @sess, cust, @params
cust.update_passphrase @params[:currentp]
obj.raise_concerns
obj.process
[cust.role, cust.verified, cust.passphrase]
#=> ['user_deleted_self', 'false', '']

## Destroyed account gets a new api key
cust = OT::Customer.new generate_random_email
first_token = cust.regenerate_apitoken  # first we need to set an api key
obj = OT::Logic::DestroyAccount.new @sess, cust, @params
cust.update_passphrase @params[:currentp]
obj.raise_concerns
obj.process
first_token.eql?(cust.apitoken)
#=> false


@sess.event_clear! :destroy_account

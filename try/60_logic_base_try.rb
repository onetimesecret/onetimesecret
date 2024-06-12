# frozen_string_literal: true

require_relative '../lib/onetime'

# frozen_string_literal: true

require_relative '../lib/onetime'

# Load the app
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.boot! :app

# Setup some variables for these tryouts
@now = DateTime.now
@from_address = OT.conf[:emailer][:from]
@email_address = 'tryouts@onetimesecret.com'
@sess = OT::Session.new
@cust = OT::Customer.new @email_address
@sess.event_clear! :send_feedback
@params = {}
@locale = 'en'
@obj = OT::Logic::CreateAccount.new @sess, @cust

# TRYOUTS

## Can create CreateAccount instance
@obj.class
#=> Onetime::Logic::CreateAccount

## Knows an invalid address
@obj.valid_email?('bogusjourney')
#=> false

## Knows a valid email address
@obj.valid_email?(@email_address)
#=> true

## Can't tell the diff between a valid email syntax and a deliverable
## email address. The default from address is changeme@example.com so
# @ it's a valid email string but not an actual, real mailbox.
##
## This is b/c currently we only perform regex validation.
##
@obj.valid_email?(@from_address)
#=> true

# tests/unit/ruby/try/17_mail_validation.rb

# These tryouts test the email validation functionality using the Truemail gem.
# Email validation is crucial for ensuring that user-provided email addresses
# are valid and potentially deliverable.
#
# We're testing various aspects of email validation, including:
# 1. Configuration of Truemail settings
# 2. Validation of various email formats (valid, invalid, edge cases)
# 3. Different validation methods (regex, MX, SMTP)
#
# These tests aim to ensure that the application can accurately validate
# email addresses, which is important for user registration and communication.

require 'digest'
require 'dotenv'
require 'truemail'

Dotenv.load('.env')

# Relys on environment variables:
# - VERIFIER_EMAIL
# - VERIFIER_DOMAIN
#
# e.g. Make sure to set these in your .env file:

require_relative './test_helpers'
OT.boot! :test, false

@now = DateTime.now
@unique_random_inbox = Digest::SHA2.hexdigest(@now.to_s)

@from_address = OT.conf[:emailer][:from]
@valid_exists = 'tryouts@onetimesecret.com'
@user_does_not_exist = "#{@unique_random_inbox}@yahoo.com"

@invalid_bad_syntax = '$tryouts@onetimesecret.com'
@invalid_no_domain = 'tryouts@'
@invalid_no_user = '@onetimesecret.com'
@invalid_no_tld = 'tryouts@onetimesecret'

@unknown_tld = 'tryouts@onetimesecret.p.bs'
@unknown_domain = 'tryouts@1800dotsup3rbogusd0main.net'

@sms_email = '5551234567@txt.att.net'


# TRYOUTS

## Sets the Truemail verifier email address
Truemail.configuration.verifier_email.nil?
#=> false

## Truemail has the configured verifier email
Truemail.configuration.verifier_email
#=> OT.conf[:mail][:truemail][:verifier_email]

## Truemail has the configured verifier domain
Truemail.configuration.verifier_domain
#=> OT.conf[:mail][:truemail][:verifier_domain]

## Truemail connection_timeout
Truemail.configuration.connection_timeout
#=> 1

## Truemail connection_attempts
Truemail.configuration.connection_attempts
#=> 1

## Knows an email address needs a domain
Truemail.valid?(@invalid_no_domain)
#=> false

## Knows an email address needs a user
Truemail.valid?(@invalid_no_user)
#=> false

## Knows a valid email address
Truemail.validate(@valid_exists, with: :regex).result.valid?
#=> true

## Knows another invalid email address
Truemail.validate(@invalid_bad_syntax, with: :regex).result.valid?
#=> false

## Knows a valid email address with an invalid TLD, _looks_ valid
Truemail.validate(@unknown_tld, with: :regex).result.valid?
#=> true

## Knows a valid email address with an invalid TLD, is not actually valid
Truemail.validate(@unknown_tld, with: :mx).result.valid?
#=> false

## Knows a valid email address with a domain that doesn't exist, _looks_ valid
Truemail.validate(@unknown_domain, with: :regex).result.valid?
#=> true

## Knows a valid email address with a domain that doesn't exist, _looks_ valid
Truemail.validate(@unknown_domain, with: :mx).result.valid?
#=> false

## Knows a valid email address syntax, but fake user is technically correct
Truemail.validate(@user_does_not_exist, with: :regex).result.valid?
#=> true

### Knows a valid email address syntax, but fake user is still a pass according to DNS
Truemail.validate(@user_does_not_exist, with: :mx).result.valid?
#=> true

## Knows a valid email address syntax, but fake user is a pass (why doesn't the smtp server say it doesn't know the user?)
Truemail.validate(@user_does_not_exist, with: :smtp).result.valid?
#=> true

## Knowns a text message email address is valid
Truemail.validate(@sms_email, with: :smtp).result.valid?
#=> true

## Truemail knows a valid email address (via regex)
Truemail.validate(@valid_exists, with: :regex).result.valid?
#=> true

## Truemail knows a valid email address (via mx)
Truemail.validate(@valid_exists, with: :mx).result.valid?
#=> true

## Truemail knows a valid email address (via smtp)
Truemail.validate(@valid_exists, with: :smtp).result.valid?
#=> true

## Truemail knows an invalid email address (via regex)
Truemail.validate(@invalid_no_domain, with: :regex).result.valid?
#=> false

## Truemail knows an invalid email address (via mx)
Truemail.validate(@invalid_no_tld, with: :mx).result.valid?
#=> false

## Truemail knows an invalid email address (via smtp)
Truemail.validate(@invalid_no_tld, with: :smtp).result.valid?
#=> false

## Truemail knows an invalid email address (via smtp)
Truemail.validate(@invalid_no_tld).result.valid?
#=> false

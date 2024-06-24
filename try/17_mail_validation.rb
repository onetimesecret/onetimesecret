# frozen_string_literal: true

require 'dotenv'
Dotenv.load('.env')

# OT.ld "11111111 #{ENV.keys.sort}"

# Relys on environment variables:
# - VERIFIER_EMAIL
# - VERIFIER_DOMAIN
#
# e.g. run `source .env` before running this tryout

require_relative '../lib/onetime'
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.boot! :app

@now = DateTime.now
@from_address = OT.conf[:emailer][:from]
@email_address = 'tryouts@onetimesecret.com'

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
#=> 2

## Truemail knows an invalid email address
Truemail.valid?(Onetime.global_secret)
#=> false

## Truemail knows a valid email address
validator = Truemail.validate('test@onetimesecret.com', with: :regex)
validator.result.valid?
#=> true

## Truemail knows another invalid email address
validator = Truemail.validate('-_test@onetimesecret.com', with: :regex)
validator.result.valid?
#=> false

## Truemail knows yet another invalid email address
validator = Truemail.validate('test@onetimesecret.c.n', with: :regex)
validator.result.valid?
#=> false

## Truemail knows an allow listed email
validator = Truemail.validate(
  'tryouts+test1@onetimesecret.com',
  #   with: :regex,
  custom_configuration: @truemail_test_config
)
validator.result.valid?
#=> true

## Truemail knows a deny listed email
validator = Truemail.validate(
  'tryouts+test3@onetimesecret.com',
  #   with: :regex,
  custom_configuration: @truemail_test_config
)
validator.result.valid?
#=> false
#
## Truemail knows a valid email address (via regex)
Truemail.validate(@email_address, with: :regex).result.valid?
#=> true

## Truemail knows a valid email address (via mx)
Truemail.validate(@email_address, with: :mx).result.valid?
#=> true

## Truemail knows a valid email address (via smtp)
Truemail.validate(@email_address, with: :smtp).result.valid?
#=> true

## Truemail knows an invalid email address (via regex)
Truemail.validate('tryouts@onetimesecret').result.valid?
#=> false

## Truemail knows an invalid email address (via mx)
Truemail.validate('tryouts@onetimesecret').result.valid?
#=> false

## Truemail knows an invalid email address (via smtp)
Truemail.validate('tryouts@onetimesecret').result.valid?
#=> false

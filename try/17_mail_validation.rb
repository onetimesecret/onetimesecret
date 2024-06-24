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


## Truemail has the configured verifier email
Truemail.configuration.verifier_email
#=> OT.conf[:mail][:truemail][:verifier_email]

## Truemail has the configured verifier domain
Truemail.configuration.verifier_domain
#=> OT.conf[:mail][:truemail][:verifier_domain]

## Truemail connection_timeout
Truemail.configuration.connection_timeout
#=> 2

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

# frozen_string_literal: true

require_relative '../lib/onetime'

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.boot! :cli

@email_address = OT.conf[:emailer][:from]

@truemail_test_config = Truemail::Configuration.new do |config|
  config.verifier_email = @email_address

  config.whitelisted_emails = [
    'tryouts+test1@onetimesecret.com',
    'tryouts+test2@onetimesecret.com'
  ]
  config.blacklisted_emails = [
    'tryouts+test3@onetimesecret.com',
    'tryouts+test4@onetimesecret.com'
  ]
end

## Finds a config path
relative_path = Onetime::Config.path.gsub("#{__dir__}/", '')
relative_path
#=> "../etc/config.test"

## Can load config
@config = Onetime::Config.load
@config.class
#=> Hash

## Has basic config
[@config[:site].class, @config[:redis].class]
#=> [Hash, Hash]

## OT.boot!
OT.boot! :tryouts
[OT.mode, OT.conf.class]
#=> [:tryouts, Hash]

## Has global secret
Onetime.global_secret.nil?
#=> false

## Has default global secret
Onetime.global_secret
#=> 'SuP0r_53cRU7'

## Sets the Truemail verifier email address
Truemail.configuration.verifier_email.nil?
#=> false

## Sets the Truemail verifier email address to the default from address
Truemail.configuration.verifier_email
#=> 'changeme@example.com'

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

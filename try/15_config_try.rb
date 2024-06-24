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

## Config.mapped_key takens an internal key and returns the corresponding external key
Onetime::Config.mapped_key(:example_internal_key)
#=> :example_external_key

## Config.mapped_key returns the key itself if it is not in the KEY_MAP
Onetime::Config.mapped_key(:every_developer_a_key)
#=> :every_developer_a_key

## Config.find_configs returns an array of paths
paths = Onetime::Config.find_configs('config.test')
paths.contains?(File.join(__dir__, '..', 'etc', 'config.test'))
#=> true

## Config.exists? knows if the config file exists
Config.exists?
#=> true

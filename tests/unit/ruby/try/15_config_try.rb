# tests/unit/ruby/try/15_config_try.rb

# These tryouts test the configuration functionality of the Onetime application.
# The Config module is responsible for loading and managing application settings.
#
# We're testing various aspects of the configuration, including:
# 1. Loading and accessing config files
# 2. Verifying basic configuration structure
# 3. Checking specific configuration options (e.g., authentication, email settings)
# 4. Testing utility methods for config key mapping and file existence
#
# These tests aim to ensure that the application can correctly load and use
# its configuration, which is crucial for proper operation and customization.

require_relative './test_helpers'

# Use the default config file for tests
OT.boot! :test

@email_address = OT.conf[:emailer][:from]


## Finds a config path
[Onetime::Config.path.nil?, Onetime::Config.path.include?('config.test.yaml')]
#=> [false, true]

## Can load config
@config = Onetime::Config.load
@config.class
#=> Hash

## Has basic config
[@config[:site].class, @config[:redis].class]
#=> [Hash, Hash]

## OT.boot! :test
OT.boot! :test
[OT.mode, OT.conf.class]
#=> [:test, Hash]

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

## Config.find_configs returns an array of paths, but the test config isn't there
paths = Onetime::Config.find_configs('config.test.yaml')
path = File.expand_path(File.join(__dir__, '..', 'config.test.yaml'))
paths.include?(path)
#=> false

## Config.find_configs returns an array of paths, where it finds the example config
paths = Onetime::Config.find_configs('config.example.yaml')
path = File.expand_path(File.join(Onetime::HOME, 'etc', 'config.example.yaml'))
puts paths
paths.include?(path)
#=> true

## Config.exists? knows if the config file exists
OT::Config.exists?
#=> true

## Site has options for authentication
OT.conf[:site].key? :authentication
#=> true

## Authentication has options for enabled
OT.conf[:site][:authentication].key? :enabled
#=> true

## Authentication is enabled by default
OT.conf[:site][:authentication][:enabled]
#=> true

## Signup is enabled by default
OT.conf[:site][:authentication][:signup]
#=> true

## Signin is enabled by default
OT.conf[:site][:authentication][:signin]
#=> true

## Auto-verification is disabled by default
OT.conf[:site][:authentication][:autoverify]
#=> false

## Option for emailer
OT.conf[:emailer][:from]
#=> "tests@example.com"

## An exception is raised if authentication config is missing
site_authentication = OT.conf[:site].delete(:authentication)
begin
  OT::Config.after_load(OT.conf)
rescue OT::Problem => e
  puts "Error: #{e}"
  OT.conf[:site][:authentication] = site_authentication # restore
  e.message.include?('No `site.authentication` config found')
end
#=> true

## An exception is raised if development config is missing
development = OT.conf.delete(:development)
begin
  OT::Config.after_load(OT.conf)
rescue OT::Problem => e
  puts "Error: #{e}"
  OT.conf[:development] = development # restore
  e.message.include?('No `development` config found')
end
#=> true

## An exception is raised if mail config is missing
mail = OT.conf.delete(:mail)
begin
  OT::Config.after_load(OT.conf)
rescue OT::Problem => e
  puts "Error: #{e}"
  OT.conf[:mail] = mail # restore
  e.message.include?('No `mail` config found')
end
#=> true

## (1 of 3) When authentication is disabled, sign-in is disabled regardless of the setting
OT.conf[:site][:authentication][:enabled] = false
OT.conf[:site][:authentication][:signin] = true
OT::Config.after_load(OT.conf)
OT.conf.dig(:site, :authentication, :signin)
#=> false

## (2 of 3) When authentication is disabled, sign-up is disabled regardless of the setting
OT.conf[:site][:authentication][:enabled] = false
OT.conf[:site][:authentication][:signup] = true
OT::Config.after_load(OT.conf)
OT.conf.dig(:site, :authentication, :signup)
#=> false

## (3 of 3) When authentication is disabled, auto-verify is disabled regardless of the setting
OT.conf[:site][:authentication][:enabled] = false
OT.conf[:site][:authentication][:enabled] = true
OT::Config.after_load(OT.conf)
OT.conf.dig(:site, :authentication, :signin)
#=> false

## Default emailer mode is :smtp
OT.conf[:emailer][:mode]
#=> "smtp"

## Default emailer from address is "CHANGEME@example.com"
OT.conf[:emailer][:from]
#=> "tests@example.com"

## Default emailer fromname is "Jan"
OT.conf[:emailer][:fromname]
#=> "Jan"

## Default SMTP host is "localhost"
OT.conf[:emailer][:host]
#=> "localhost"

## Default SMTP port is 587
OT.conf[:emailer][:port]
#=> 587

## Default SMTP username is "CHANGEME"
OT.conf[:emailer][:user]
#=> "user"

## Default SMTP password is "CHANGEME"
OT.conf[:emailer][:pass]
#=> "pass"

## Default SMTP auth is "login"
OT.conf[:emailer][:auth]
#=> "login"

## Default SMTP TLS is true
OT.conf[:emailer][:tls]
#=> true

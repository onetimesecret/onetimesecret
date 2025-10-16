# try/15_config_try.rb

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

require_relative '../../support/test_helpers'

OT.boot! :test, false

@email_address = OT.conf['emailer']['from']


## Finds a config path
[Onetime::Config.path.nil?, Onetime::Config.path.include?('config.test.yaml')]
#=> [false, true]

## Can load config
@config = Onetime::Config.load
@config.class
#=> Hash

## Has basic config
[@config['site'].class, @config['redis'].class]
#=> [Hash, Hash]

## OT.boot! :test, false
[OT.mode, OT.conf.class]
#=> [:test, Hash]

## Has global secret
Onetime.global_secret.nil?
#=> false

## Has default global secret
Onetime.global_secret
#=> 'SuP0r_53cRU7_t3st_0nly'

## Config.mapped_key takens an internal key and returns the corresponding external key
Onetime::Config.mapped_key('example_internal_key')
#=> 'example_external_key'

## Config.mapped_key returns the key itself if it is not in the KEY_MAP (symbol)
Onetime::Config.mapped_key(:every_developer_a_key)
#=> :every_developer_a_key

## Config.mapped_key returns the key itself if it is not in the KEY_MAP (string)
Onetime::Config.mapped_key('every_developer_a_string_key')
#=> 'every_developer_a_string_key'

## Config.find_configs returns an array of paths, but the test config isn't there
paths = Onetime::Config.find_configs('config.test.yaml')
path = File.expand_path(File.join(__dir__, '..', 'config.test.yaml'))
paths.include?(path)
#=> false

## Config.find_configs returns an array of paths, where it finds the example config
paths = Onetime::Config.find_configs('config.defaults.yaml')
path = File.expand_path(File.join(Onetime::HOME, 'etc', 'defaults', 'config.defaults.yaml'))
paths.include?(path)
#=> true

## Site has options for authentication
OT.conf['site'].key? 'authentication'
#=> true

## Authentication has options for enabled
OT.conf['site']['authentication'].key? 'enabled'
#=> true

## Authentication is enabled by default
OT.conf['site']['authentication']['enabled']
#=> true

## Signup is enabled by default
OT.conf['site']['authentication']['signup']
#=> true

## Signin is enabled by default
OT.conf['site']['authentication']['signin']
#=> true

## Auto-verification is disabled by default
OT.conf['site']['authentication']['autoverify']
#=> false

## Option for emailer
OT.conf['emailer']['from']
#=> "tests@example.com"

## Default emailer mode is :smtp
OT.conf['emailer']['mode']
#=> "smtp"

## Default emailer from address is "CHANGEME@example.com"
OT.conf['emailer']['from']
#=> "tests@example.com"

## Default emailer fromname is "Jan"
OT.conf['emailer']['fromname']
#=> "Jan"

## Default SMTP host is "localhost"
OT.conf['emailer']['host']
#=> "localhost"

## Default SMTP port is 587
OT.conf['emailer']['port']
#=> 587

## Default SMTP username is "CHANGEME"
OT.conf['emailer']['user']
#=> "user"

## Default SMTP password is "CHANGEME"
OT.conf['emailer']['pass']
#=> "pass"

## Default SMTP auth is "login"
OT.conf['emailer']['auth']
#=> "login"

## Default SMTP TLS is true
OT.conf['emailer']['tls']
#=> true

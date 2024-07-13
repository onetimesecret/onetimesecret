# frozen_string_literal: true

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

require_relative '../lib/onetime'

# Use the default config file for tests
OT::Config.path = File.join(__dir__, '..', 'etc', 'config.test')
OT.boot! :cli

@email_address = OT.conf[:emailer][:from]


## Finds a config path
Onetime::Config.path.gsub("#{__dir__}/", '')
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
path = File.expand_path(File.join(__dir__, '..', 'etc', 'config.test'))
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

## Option for emailer
OT.conf[:emailer][:from]
#=> "CHANGEME@example.com"

# tests/unit/ruby/try/16_config_secret_options_try.rb

# These tryouts test the secret_options configuration of the Onetime application.
# We're testing various aspects of the secret_options configuration, including:
# 1. Loading and accessing the secret_options configuration
# 2. Verifying the structure of secret_options
# 3. Checking specific configuration options (e.g., default_ttl, ttl_options)
# 4. Testing the behavior with different environment variable settings

require_relative '../helpers/test_helpers'

# Use the default config file for tests
OT.boot! :test, false

## Config has secret_options
OT.conf[:site].key? :secret_options
#=> true

## secret_options has default_ttl
OT.conf[:site][:secret_options].key? :default_ttl
#=> true

## secret_options has ttl_options
OT.conf[:site][:secret_options].key? :ttl_options
#=> true

## Default TTL is 604800 (7 days) when ENV['DEFAULT_TTL'] is not set
ENV['DEFAULT_TTL'] = nil
OT.boot! :test, false
OT.conf[:site][:secret_options][:default_ttl]
#=> 43200

## Default TTL is updated when ENV['DEFAULT_TTL'] is provided
ENV['DEFAULT_TTL'] = '3600'
OT.boot! :test, false
OT.conf[:site][:secret_options][:default_ttl]
#=> 3600

## TTL options are an array of integers when ENV['TTL_OPTIONS'] is not set
ENV['TTL_OPTIONS'] = nil
OT.boot! :test, false
OT.conf[:site][:secret_options][:ttl_options]
#=> [1800, 43200, 604800]

## TTL options are updated when ENV['TTL_OPTIONS'] is provided
ENV['TTL_OPTIONS'] = '300 3600 86400'
OT.boot! :test, false
OT.conf[:site][:secret_options][:ttl_options]
#=> [300, 3600, 86400]

# Clean up environment variables after tests
ENV['DEFAULT_TTL'] = nil
ENV['TTL_OPTIONS'] = nil

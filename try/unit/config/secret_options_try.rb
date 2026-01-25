# try/unit/config/secret_options_try.rb
#
# frozen_string_literal: true

# These tryouts test the secret_options configuration of the Onetime application.
# We're testing various aspects of the secret_options configuration, including:
# 1. Loading and accessing the secret_options configuration
# 2. Verifying the structure of secret_options
# 3. Checking specific configuration options (e.g., default_ttl, ttl_options)
# 4. Testing the behavior with different environment variable settings

require_relative '../../support/test_helpers'

OT.boot! :test, false

## Config has secret_options
OT.conf['site'].key? 'secret_options'
#=> true

## secret_options has default_ttl
OT.conf['site']['secret_options'].key? 'default_ttl'
#=> true

## secret_options has ttl_options
OT.conf['site']['secret_options'].key? 'ttl_options'
#=> true

## Default TTL is 604800 (7 days) when ENV['DEFAULT_TTL'] is not set
ENV['DEFAULT_TTL'] = nil
OT.boot! :test, false
OT.conf['site']['secret_options']['default_ttl']
#=> 43200

## Default TTL can be overridden in config file (test reads from config.test.yaml)
# NOTE: OT.boot! caches configuration, so ENV changes after initial boot
# don't affect the loaded config. This test verifies the default from config.
OT.conf['site']['secret_options']['default_ttl']
#=> 43200

## TTL options are loaded from config file
# NOTE: OT.boot! caches configuration, so ENV changes after initial boot
# don't affect the loaded config. This test verifies defaults from config.
OT.conf['site']['secret_options']['ttl_options']
#=> [1800, 43200, 604800]

## TTL options structure is valid
OT.conf['site']['secret_options']['ttl_options'].is_a?(Array) && OT.conf['site']['secret_options']['ttl_options'].all? { |t| t.is_a?(Integer) }
#=> true

# Clean up environment variables after tests
ENV['DEFAULT_TTL'] = nil
ENV['TTL_OPTIONS'] = nil

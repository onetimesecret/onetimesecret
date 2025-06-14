# frozen_string_literal: true

# These tryouts test the TrueMail configuration integration in the Onetime application.
# They cover:
#
# 1. Key mapping between OneTime's naming conventions and TrueMail's API
# 2. Validation of required TrueMail configuration
# 3. Application of default and custom settings
#
# These tests ensure that email validation is properly configured and
# that our custom mapping layer works correctly with the TrueMail library.

require 'onetime'

# Use the default config file for tests
OT::Configurator.path = File.join(Onetime::HOME, 'tests', 'unit', 'ruby', 'config.test.yaml')
OT.boot! :test

## mapped_key converts allowed_domains_only to whitelist_validation
OT::Configurator.mapped_key(:allowed_domains_only)
#=> :whitelist_validation

## mapped_key converts allowed_emails to whitelisted_emails
OT::Configurator.mapped_key(:allowed_emails)
#=> :whitelisted_emails

## mapped_key converts blocked_emails to blacklisted_emails
OT::Configurator.mapped_key(:blocked_emails)
#=> :blacklisted_emails

## mapped_key converts allowed_domains to whitelisted_domains
OT::Configurator.mapped_key(:allowed_domains)
#=> :whitelisted_domains

## mapped_key converts blocked_domains to blacklisted_domains
OT::Configurator.mapped_key(:blocked_domains)
#=> :blacklisted_domains

## mapped_key converts blocked_mx_ip_addresses to blacklisted_mx_ip_addresses
OT::Configurator.mapped_key(:blocked_mx_ip_addresses)
#=> :blacklisted_mx_ip_addresses

## mapped_key returns unmapped keys as-is
OT::Configurator.mapped_key(:unmapped_key)
#=> :unmapped_key

## Config contains expected TrueMail settings from test config
OT.conf[:mail][:truemail][:default_validation_type]
#=> :mx

## Config loads DNS servers from test config
OT.conf[:mail][:truemail][:dns].include?('1.1.1.1')
#=> true

## Config loads connection settings from test config
OT.conf[:mail][:truemail][:connection_timeout]
#=> 1

## Config loads SMTP settings from test config
OT.conf[:mail][:truemail][:smtp_fail_fast]
#=> true

## apply_defaults preserves original sections and doesn't change defaults
config = {
  defaults: { timeout: 5, enabled: true },
  api: { timeout: 10 },
  web: {}
}
original_defaults = config[:defaults].dup
result = OT::Configurator.apply_defaults_to_peers(config)
[result[:api][:timeout], result[:web][:timeout], result[:api][:enabled], config[:defaults] == original_defaults]
#=> [10, 5, true, true]

## apply_defaults handles nil config
OT::Configurator.apply_defaults_to_peers(nil)
#=> {}

## apply_defaults handles empty config
OT::Configurator.apply_defaults_to_peers({})
#=> {}

## apply_defaults preserves defaults when section value is nil
config = {
  defaults: { dsn: 'default-dsn' },
  backend: { dsn: nil },
  frontend: { dsn: nil }
}
result = OT::Configurator.apply_defaults_to_peers(config)
[result[:backend][:dsn], result[:frontend][:dsn]]
#=> ['default-dsn', 'default-dsn']

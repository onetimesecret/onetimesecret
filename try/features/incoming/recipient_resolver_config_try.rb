# try/features/incoming/recipient_resolver_config_try.rb
#
# frozen_string_literal: true

# These tryouts test that RecipientResolver.config_data returns
# the correct TTL and memo_max_length values for both canonical
# and custom domain strategies. This validates Item 4 fix:
# per-domain config values should be used instead of global YAML.

require_relative '../../support/test_models'
OT.boot! :test, false

require 'onetime/incoming/recipient_resolver'

RecipientResolver = Onetime::Incoming::RecipientResolver
IncomingSecretsConfig = Onetime::CustomDomain::IncomingSecretsConfig

## Canonical domain uses global YAML config for default_ttl
resolver = RecipientResolver.new(domain_strategy: :canonical)
config = resolver.config_data
# Default from test config is 604800 (7 days)
config[:default_ttl]
#=> 604_800

## Canonical domain uses global YAML config for memo_max_length
resolver = RecipientResolver.new(domain_strategy: :canonical)
config = resolver.config_data
# Default from test config is 50
config[:memo_max_length]
#=> 50

## Nil domain strategy behaves like canonical
resolver = RecipientResolver.new(domain_strategy: nil)
config = resolver.config_data
[config[:default_ttl], config[:memo_max_length]]
#=> [604_800, 50]

## config_data returns defaults when custom domain has no incoming config
# Create resolver for a non-existent custom domain
resolver = RecipientResolver.new(
  domain_strategy: :custom,
  display_domain: 'nonexistent.example.com'
)
config = resolver.config_data
# Should return defaults since domain doesn't exist
[config[:default_ttl], config[:memo_max_length]]
#=> [604_800, 50]

## config_data includes enabled status
resolver = RecipientResolver.new(domain_strategy: :canonical)
config = resolver.config_data
config.key?(:enabled)
#=> true

## config_data includes recipients list
resolver = RecipientResolver.new(domain_strategy: :canonical)
config = resolver.config_data
config[:recipients].is_a?(Array)
#=> true

## IncomingSecretsConfig DEFAULTS match what resolver expects
defaults = IncomingSecretsConfig::DEFAULTS
[defaults[:memo_max_length], defaults[:default_ttl]]
#=> [50, 604_800]

# try/unit/domain_validation/provider_config_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::DomainValidation::SenderStrategies::ProviderConfig
#
# Validates:
# 1. Default values are returned when no config present
# 2. Config values from OT.conf override defaults
# 3. Explicit overrides take precedence over config
# 4. Available providers includes both defaults and config providers
# 5. Symbolization of string keys from YAML config

require_relative '../../support/test_helpers'

OT.boot! :test

require 'onetime/domain_validation/sender_strategies/provider_config'

ProviderConfig = Onetime::DomainValidation::SenderStrategies::ProviderConfig

# --- Default values (no config) ---

## SES default region is us-east-1
config = ProviderConfig.for('ses')
config[:region]
#=> 'us-east-1'

## SES default dkim_selector_count is 3
config = ProviderConfig.for('ses')
config[:dkim_selector_count]
#=> 3

## SES default spf_include is amazonses.com
config = ProviderConfig.for('ses')
config[:spf_include]
#=> 'amazonses.com'

## SendGrid default subdomain is em
config = ProviderConfig.for('sendgrid')
config[:subdomain]
#=> 'em'

## SendGrid default dkim_selectors are s1, s2
config = ProviderConfig.for('sendgrid')
config[:dkim_selectors]
#=> ['s1', 's2']

## SendGrid default spf_include is sendgrid.net
config = ProviderConfig.for('sendgrid')
config[:spf_include]
#=> 'sendgrid.net'

## Lettermint default dkim_selectors are lm1, lm2
config = ProviderConfig.for('lettermint')
config[:dkim_selectors]
#=> ['lm1', 'lm2']

## Lettermint default spf_include is lettermint.com
config = ProviderConfig.for('lettermint')
config[:spf_include]
#=> 'lettermint.com'

# --- Explicit overrides take precedence ---

## Explicit region override for SES
config = ProviderConfig.for('ses', region: 'eu-west-1')
config[:region]
#=> 'eu-west-1'

## Explicit subdomain override for SendGrid
config = ProviderConfig.for('sendgrid', subdomain: 'mail')
config[:subdomain]
#=> 'mail'

## Explicit dkim_selectors override for Lettermint
config = ProviderConfig.for('lettermint', dkim_selectors: ['custom1', 'custom2', 'custom3'])
config[:dkim_selectors]
#=> ['custom1', 'custom2', 'custom3']

## Multiple overrides merge with defaults
config = ProviderConfig.for('ses', region: 'ap-northeast-1', dkim_selector_count: 5)
[config[:region], config[:dkim_selector_count], config[:spf_include]]
#=> ['ap-northeast-1', 5, 'amazonses.com']

# --- Unknown provider returns empty hash ---

## Unknown provider returns empty hash
config = ProviderConfig.for('unknown_provider')
config
#=> {}

## Unknown provider with overrides returns just overrides
config = ProviderConfig.for('unknown_provider', custom_setting: 'value')
config[:custom_setting]
#=> 'value'

# --- Provider name normalization ---

## Provider name is case-insensitive
config_lower = ProviderConfig.for('ses')
config_upper = ProviderConfig.for('SES')
config_mixed = ProviderConfig.for('SeS')
config_lower[:region] == config_upper[:region] && config_upper[:region] == config_mixed[:region]
#=> true

## Provider name is stripped of whitespace
config = ProviderConfig.for('  ses  ')
config[:region]
#=> 'us-east-1'

# --- Available providers ---

## available_providers includes all default providers
providers = ProviderConfig.available_providers
providers.include?('ses') && providers.include?('sendgrid') && providers.include?('lettermint')
#=> true

## available_providers returns sorted array
providers = ProviderConfig.available_providers
providers == providers.sort
#=> true

# --- Symbol keys are always returned ---

## Config returns symbol keys, not string keys
config = ProviderConfig.for('ses')
config.keys.all? { |k| k.is_a?(Symbol) }
#=> true

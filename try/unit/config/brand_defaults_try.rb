# try/unit/config/brand_defaults_try.rb
#
# frozen_string_literal: true

# Tests for the brand configuration resolution chain.
#
# The brand config section in config.defaults.yaml provides:
# - primary_color: from ENV['BRAND_PRIMARY_COLOR'] or '#dc4a22'
# - product_name: from ENV['BRAND_PRODUCT_NAME'] or 'OTS'
# - product_domain: from ENV['BRAND_PRODUCT_DOMAIN'] or nil
#
# BrandSettingsConstants.defaults reads primary_color from OT.conf
# and falls back to the frozen DEFAULTS constant.

require_relative '../../support/test_helpers'

OT.boot! :test, false

## Config has a brand section
OT.conf.key?('brand')
#=> true

## Brand primary_color has a default value
color = OT.conf.dig('brand', 'primary_color')
color.nil? || color.match?(/^#[0-9A-Fa-f]{6}$/)
#=> true

## Brand product_name has a default value
name = OT.conf.dig('brand', 'product_name')
name.nil? || name.is_a?(String)
#=> true

## BrandSettingsConstants::DEFAULTS has primary_color
Onetime::CustomDomain::BrandSettingsConstants::DEFAULTS[:primary_color]
#=> '#dc4a22'

## BrandSettingsConstants.defaults returns a hash with primary_color
defaults = Onetime::CustomDomain::BrandSettingsConstants.defaults
defaults[:primary_color].match?(/^#[0-9A-Fa-f]{6}$/)
#=> true

## BrandSettingsConstants.defaults reads from config when available
defaults = Onetime::CustomDomain::BrandSettingsConstants.defaults
config_color = OT.conf.dig('brand', 'primary_color')
# If config has a color, defaults should use it; otherwise falls back to DEFAULTS
if config_color
  defaults[:primary_color] == config_color
else
  defaults[:primary_color] == '#dc4a22'
end
#=> true

## BrandSettings.from_hash uses dynamic defaults for primary_color
settings = Onetime::CustomDomain::BrandSettings.from_hash({})
settings.primary_color.match?(/^#[0-9A-Fa-f]{6}$/)
#=> true

## BrandSettings.from_hash allows overriding primary_color
settings = Onetime::CustomDomain::BrandSettings.from_hash(primary_color: '#FF0000')
settings.primary_color
#=> '#FF0000'

## ENV override for brand primary color works
# Must load the ERB-templated defaults file (not the static test config)
# to verify ENV substitution in the config template.
@defaults_path = File.join(Onetime::HOME, 'etc', 'defaults', 'config.defaults.yaml')
with_env('BRAND_PRIMARY_COLOR', '#00FF00') do
  config = Onetime::Config.load(@defaults_path)
  config.dig('brand', 'primary_color')
end
#=> '#00FF00'

## ENV override for brand product name works
with_env('BRAND_PRODUCT_NAME', 'My Custom App') do
  config = Onetime::Config.load(@defaults_path)
  config.dig('brand', 'product_name')
end
#=> 'My Custom App'

## Brand totp_issuer has a default value
issuer = OT.conf.dig('brand', 'totp_issuer')
issuer.nil? || issuer.is_a?(String)
#=> true

## Brand totp_issuer is nil when not configured
OT.conf.dig('brand', 'totp_issuer')
#=> nil

## ENV override for brand totp_issuer works
with_env('BRAND_TOTP_ISSUER', 'My Custom Issuer') do
  config = Onetime::Config.load(@defaults_path)
  config.dig('brand', 'totp_issuer')
end
#=> 'My Custom Issuer'

## TOTP utility default_issuer reads from config
require_relative '../../../lib/onetime/utils/totp'
Onetime::Utils::TOTP.default_issuer
#=> 'OTS'

## BrandSettings.members includes product_name
Onetime::CustomDomain::BrandSettings.members.include?(:product_name)
#=> true

## BrandSettings.members includes footer_text
Onetime::CustomDomain::BrandSettings.members.include?(:footer_text)
#=> true

## BrandSettings.members includes description
Onetime::CustomDomain::BrandSettings.members.include?(:description)
#=> true

## BrandSettings.members includes product_domain
Onetime::CustomDomain::BrandSettings.members.include?(:product_domain)
#=> true

## BrandSettings.members includes support_email
Onetime::CustomDomain::BrandSettings.members.include?(:support_email)
#=> true

## BrandSettings.members includes all expected text fields
expected = %i[product_name footer_text description product_domain support_email]
(expected - Onetime::CustomDomain::BrandSettings.members).empty?
#=> true

## BrandSettings.from_hash preserves product_name when provided
settings = Onetime::CustomDomain::BrandSettings.from_hash(product_name: 'My App')
settings.product_name
#=> 'My App'

## BrandSettings.from_hash preserves footer_text when provided
settings = Onetime::CustomDomain::BrandSettings.from_hash(footer_text: 'Custom footer')
settings.footer_text
#=> 'Custom footer'

## BrandSettings.from_hash preserves description when provided
settings = Onetime::CustomDomain::BrandSettings.from_hash(description: 'A brief summary')
settings.description
#=> 'A brief summary'

## BrandSettings.from_hash preserves product_domain when provided
settings = Onetime::CustomDomain::BrandSettings.from_hash(product_domain: 'example.com')
settings.product_domain
#=> 'example.com'

## BrandSettings.from_hash preserves support_email when provided
settings = Onetime::CustomDomain::BrandSettings.from_hash(support_email: 'help@example.com')
settings.support_email
#=> 'help@example.com'

## BrandSettings.from_hash defaults missing text fields to nil
settings = Onetime::CustomDomain::BrandSettings.from_hash({})
[settings.product_name, settings.footer_text, settings.description, settings.product_domain, settings.support_email]
#=> [nil, nil, nil, nil, nil]

## BrandSettings.from_hash accepts text fields alongside existing fields
settings = Onetime::CustomDomain::BrandSettings.from_hash(
  primary_color: '#FF0000',
  product_name: 'Branded App',
  footer_text: 'Powered by us'
)
[settings.primary_color, settings.product_name, settings.footer_text]
#=> ['#FF0000', 'Branded App', 'Powered by us']

## BrandSettings.from_hash with string keys preserves text fields
settings = Onetime::CustomDomain::BrandSettings.from_hash('product_name' => 'String Key App', 'description' => 'Works too')
[settings.product_name, settings.description]
#=> ['String Key App', 'Works too']

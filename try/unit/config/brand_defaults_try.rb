# try/unit/config/brand_defaults_try.rb
#
# frozen_string_literal: true

# Tests for the brand configuration resolution chain.
#
# The brand config section in config.defaults.yaml provides:
# - primary_color: from ENV['BRAND_PRIMARY_COLOR'] or '#dc4a22'
# - product_name: from ENV['BRAND_PRODUCT_NAME'] or 'Onetime Secret'
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
with_env('BRAND_PRIMARY_COLOR', '#00FF00') do
  # Re-load config to pick up env change
  config = Onetime::Config.load
  config.dig('brand', 'primary_color')
end
#=> '#00FF00'

## ENV override for brand product name works
with_env('BRAND_PRODUCT_NAME', 'My Custom App') do
  config = Onetime::Config.load
  config.dig('brand', 'product_name')
end
#=> 'My Custom App'

## Brand totp_issuer has a default value
issuer = OT.conf.dig('brand', 'totp_issuer')
issuer.nil? || issuer.is_a?(String)
#=> true

## Brand totp_issuer defaults to OneTimeSecret
OT.conf.dig('brand', 'totp_issuer')
#=> 'OneTimeSecret'

## ENV override for brand totp_issuer works
with_env('BRAND_TOTP_ISSUER', 'My Custom Issuer') do
  config = Onetime::Config.load
  config.dig('brand', 'totp_issuer')
end
#=> 'My Custom Issuer'

## TOTP utility default_issuer reads from config
Onetime::Utils::TOTP.default_issuer
#=> 'OneTimeSecret'

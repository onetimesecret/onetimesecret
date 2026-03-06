# try/unit/config/brand_global_defaults_try.rb
#
# frozen_string_literal: true

# Tests for BrandSettingsConstants.global_defaults method.
# This method resolves global brand settings (not per-domain) from config
# with fallbacks to GLOBAL_DEFAULTS.

require_relative '../../support/test_helpers'

OT.boot! :test, false

## BrandSettingsConstants::GLOBAL_DEFAULTS has required keys
required_keys = [:support_email, :product_name, :totp_issuer, :logo_url]
(required_keys - Onetime::CustomDomain::BrandSettingsConstants::GLOBAL_DEFAULTS.keys).empty?
#=> true

## GLOBAL_DEFAULTS.support_email is set
Onetime::CustomDomain::BrandSettingsConstants::GLOBAL_DEFAULTS[:support_email]
#=> 'support@onetimesecret.com'

## GLOBAL_DEFAULTS.product_name is set
Onetime::CustomDomain::BrandSettingsConstants::GLOBAL_DEFAULTS[:product_name]
#=> 'OTS'

## GLOBAL_DEFAULTS.totp_issuer is set
Onetime::CustomDomain::BrandSettingsConstants::GLOBAL_DEFAULTS[:totp_issuer]
#=> 'OTS'

## GLOBAL_DEFAULTS.logo_url defaults to nil
Onetime::CustomDomain::BrandSettingsConstants::GLOBAL_DEFAULTS[:logo_url]
#=> nil

## global_defaults returns a hash
defaults = Onetime::CustomDomain::BrandSettingsConstants.global_defaults
defaults.is_a?(Hash)
#=> true

## global_defaults has all required keys
required_keys = [:support_email, :product_name, :totp_issuer, :logo_url]
(required_keys - Onetime::CustomDomain::BrandSettingsConstants.global_defaults.keys).empty?
#=> true

## global_defaults returns support_email
email = Onetime::CustomDomain::BrandSettingsConstants.global_defaults[:support_email]
email.is_a?(String) && !email.empty?
#=> true

## global_defaults returns product_name
name = Onetime::CustomDomain::BrandSettingsConstants.global_defaults[:product_name]
name.is_a?(String) && !name.empty?
#=> true

## global_defaults returns totp_issuer
issuer = Onetime::CustomDomain::BrandSettingsConstants.global_defaults[:totp_issuer]
issuer.is_a?(String) && !issuer.empty?
#=> true

## global_defaults.logo_url can be nil
logo = Onetime::CustomDomain::BrandSettingsConstants.global_defaults[:logo_url]
logo.nil? || logo.is_a?(String)
#=> true

## global_defaults reads from config when OT.conf is available
# In test environment, config may not have brand values, so we check if
# global_defaults returns valid values (either from config or GLOBAL_DEFAULTS)
defaults = Onetime::CustomDomain::BrandSettingsConstants.global_defaults
defaults[:support_email] == OT.conf.dig('brand', 'support_email') ||
  defaults[:support_email] == Onetime::CustomDomain::BrandSettingsConstants::GLOBAL_DEFAULTS[:support_email]
#=> true

## global_defaults product_name fallback chain works
defaults     = Onetime::CustomDomain::BrandSettingsConstants.global_defaults
config_name  = OT.conf.dig('brand', 'product_name')
config_name ? (defaults[:product_name] == config_name) : (defaults[:product_name] == 'OTS')
#=> true

## global_defaults totp_issuer fallback chain works
defaults      = Onetime::CustomDomain::BrandSettingsConstants.global_defaults
config_issuer = OT.conf.dig('brand', 'totp_issuer')
config_issuer ? (defaults[:totp_issuer] == config_issuer) : (defaults[:totp_issuer] == 'OTS')
#=> true

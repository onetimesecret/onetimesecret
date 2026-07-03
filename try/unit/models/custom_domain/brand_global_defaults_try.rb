# try/unit/models/custom_domain/brand_global_defaults_try.rb
#
# frozen_string_literal: true

#
# BrandSettingsConstants::GLOBAL_DEFAULTS regression guard (issue #3048 / #3049)
#
# Critical assertions:
#   - GLOBAL_DEFAULTS[:support_email] is neutral or nil (NOT 'support@onetimesecret.com')
#   - GLOBAL_DEFAULTS[:product_name] is nil (the #3049 stamp picked 'Secure Links' as the
#     neutral product name, not 'OTS' — each consumer owns its own neutral fallback)
#
# These tests are the regression guard against #dc4a22-style OTS-branding
# leaking into the shipped neutral defaults.
#
# All tests are FORWARD-LOOKING — GLOBAL_DEFAULTS does not exist on main yet.
#

# Pure Ruby constants — no Redis or OT.boot! required.

require 'onetime'
require 'onetime/models/custom_domain'

@constants = Onetime::CustomDomain::BrandSettingsConstants

## [forward] GLOBAL_DEFAULTS hash exists on BrandSettingsConstants
defined?(@constants::GLOBAL_DEFAULTS) ? true : false
#=> true

## [forward] GLOBAL_DEFAULTS is a Hash
@constants::GLOBAL_DEFAULTS.is_a?(Hash)
#=> true

## [forward] GLOBAL_DEFAULTS is frozen
@constants::GLOBAL_DEFAULTS.frozen?
#=> true

## [forward / regression guard] GLOBAL_DEFAULTS[:support_email] is neutral or nil
# Specifically: it must NOT be 'support@onetimesecret.com'
support = @constants::GLOBAL_DEFAULTS[:support_email]
support.nil? || support != 'support@onetimesecret.com'
#=> true

## [forward / regression guard] GLOBAL_DEFAULTS[:support_email] is NOT 'support@onetimesecret.com'
@constants::GLOBAL_DEFAULTS[:support_email] != 'support@onetimesecret.com'
#=> true

## [forward] GLOBAL_DEFAULTS[:product_name] is nil (each consumer owns its
## neutral fallback: frontend NEUTRAL_BRAND_DEFAULTS / mail NEUTRAL_PRODUCT_NAME;
## the legacy site_name tier was retired in #3612)
@constants::GLOBAL_DEFAULTS[:product_name]
#=> nil

## [forward / regression guard] GLOBAL_DEFAULTS[:product_name] is NOT 'Onetime Secret'
@constants::GLOBAL_DEFAULTS[:product_name] != 'Onetime Secret'
#=> true

## [forward / regression guard] GLOBAL_DEFAULTS[:product_name] is NOT 'OTS'
@constants::GLOBAL_DEFAULTS[:product_name] != 'OTS'
#=> true

## [forward] runtime global_defaults reader exists on BrandSettingsConstants
@constants.respond_to?(:global_defaults)
#=> true

## [forward] BrandSettingsConstants.global_defaults returns a Hash
@constants.global_defaults.is_a?(Hash)
#=> true

## [forward] runtime global_defaults product_name resolves to nil by default
@constants.global_defaults[:product_name]
#=> nil

## [forward / regression guard] runtime global_defaults support_email is neutral or nil
support = @constants.global_defaults[:support_email]
support.nil? || support != 'support@onetimesecret.com'
#=> true

## GLOBAL_DEFAULTS includes a logo_alt key defaulting to nil (#3612)
[@constants::GLOBAL_DEFAULTS.key?(:logo_alt), @constants::GLOBAL_DEFAULTS[:logo_alt]]
#=> [true, nil]

## runtime global_defaults exposes logo_alt (nil when unconfigured)
[@constants.global_defaults.key?(:logo_alt), @constants.global_defaults[:logo_alt]]
#=> [true, nil]

## runtime global_defaults logo_alt reflects brand.logo_alt when configured
@_saved_conf_alt = OT.instance_variable_get(:@conf)
begin
  OT.instance_variable_set(:@conf, { 'brand' => { 'logo_alt' => 'Acme wordmark' } })
  @constants.global_defaults[:logo_alt]
ensure
  OT.instance_variable_set(:@conf, @_saved_conf_alt)
end
#=> 'Acme wordmark'

## [regression guard] NEUTRAL_PRODUCT_NAME is 'Secure Links' — must stay in
## lockstep with the frontend NEUTRAL_BRAND_DEFAULTS.product_name
## (src/shared/constants/brand.ts) so an unbranded install reads the same
## everywhere (#3612)
@constants::NEUTRAL_PRODUCT_NAME
#=> 'Secure Links'

## totp_issuer falls back to brand.product_name when totp_issuer is unset —
## a configured product name brands new MFA enrollments too (#3612)
@_saved_conf_totp1 = OT.instance_variable_get(:@conf)
begin
  OT.instance_variable_set(:@conf, { 'brand' => { 'product_name' => 'Acme' } })
  @constants.global_defaults[:totp_issuer]
ensure
  OT.instance_variable_set(:@conf, @_saved_conf_totp1)
end
#=> 'Acme'

## totp_issuer stays 'OTS' when totp_issuer and product_name are both unset
## (pre-existing MFA enrollments keep consistent otpauth:// issuer labels)
@_saved_conf_totp2 = OT.instance_variable_get(:@conf)
begin
  OT.instance_variable_set(:@conf, { 'brand' => {} })
  @constants.global_defaults[:totp_issuer]
ensure
  OT.instance_variable_set(:@conf, @_saved_conf_totp2)
end
#=> 'OTS'

## an explicit brand.totp_issuer (BRAND_TOTP_ISSUER) wins over product_name
@_saved_conf_totp3 = OT.instance_variable_get(:@conf)
begin
  OT.instance_variable_set(:@conf, {
    'brand' => { 'totp_issuer' => 'AcmeAuth', 'product_name' => 'Acme' },
  })
  @constants.global_defaults[:totp_issuer]
ensure
  OT.instance_variable_set(:@conf, @_saved_conf_totp3)
end
#=> 'AcmeAuth'

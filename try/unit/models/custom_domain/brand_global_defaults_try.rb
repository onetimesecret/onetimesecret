# try/unit/models/custom_domain/brand_global_defaults_try.rb
#
# frozen_string_literal: true

#
# BrandSettingsConstants::GLOBAL_DEFAULTS regression guard (issue #3048 / #3049)
#
# Critical assertions:
#   - GLOBAL_DEFAULTS[:support_email] is neutral or nil (NOT 'support@onetimesecret.com')
#   - GLOBAL_DEFAULTS[:product_name] is nil (the #3049 stamp picked 'My App' as the
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

## [forward] GLOBAL_DEFAULTS[:product_name] is nil — frontend NEUTRAL_BRAND_DEFAULTS
## ('My App') and the legacy site_name fallback own the neutral default instead
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

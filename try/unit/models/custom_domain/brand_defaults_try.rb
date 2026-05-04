# try/unit/models/custom_domain/brand_defaults_try.rb
#
# frozen_string_literal: true

#
# BrandSettingsConstants::DEFAULTS regression guard (issue #3048 / #3049)
#
# Critical assertion: DEFAULTS[:primary_color] is the NEUTRAL BLUE '#3B82F6',
# NOT the OTS-orange '#dc4a22'. Per #3049 the shipped default must never
# carry OTS branding because that leaks into private-label deployments.
#
# The :primary_color default is a regression guard — if anyone reverts it
# to '#dc4a22' to restore "default OTS branding" they break the entire
# private-label stance documented in the issue.
#
# All tests below are FORWARD-LOOKING — main currently has '#dc4a22'.
#

# Pure Ruby constants — no Redis or OT.boot! required.

require 'onetime'
require 'onetime/models/custom_domain'

@constants = Onetime::CustomDomain::BrandSettingsConstants
@bs        = Onetime::CustomDomain::BrandSettings

## DEFAULTS hash exists on BrandSettingsConstants
@constants::DEFAULTS.is_a?(Hash)
#=> true

## DEFAULTS hash is frozen
@constants::DEFAULTS.frozen?
#=> true

## [forward / regression guard] DEFAULTS[:primary_color] is neutral blue (#3B82F6), NOT OTS-orange
@constants::DEFAULTS[:primary_color]
#=> '#3B82F6'

## [forward / regression guard] DEFAULTS[:primary_color] is NOT the OTS-orange #dc4a22
@constants::DEFAULTS[:primary_color] != '#dc4a22'
#=> true

## DEFAULTS[:font_family] preserved as 'sans'
@constants::DEFAULTS[:font_family]
#=> 'sans'

## DEFAULTS[:corner_style] preserved as 'rounded'
@constants::DEFAULTS[:corner_style]
#=> 'rounded'

## DEFAULTS[:locale] preserved as 'en'
@constants::DEFAULTS[:locale]
#=> 'en'

## [forward] DEFAULTS[:button_text_light] is now true (flipped from false)
@constants::DEFAULTS[:button_text_light]
#=> true

## DEFAULTS[:allow_public_homepage] preserved as false
@constants::DEFAULTS[:allow_public_homepage]
#=> false

## DEFAULTS[:allow_public_api] preserved as false
@constants::DEFAULTS[:allow_public_api]
#=> false

## DEFAULTS[:passphrase_required] preserved as false
@constants::DEFAULTS[:passphrase_required]
#=> false

## DEFAULTS[:notify_enabled] preserved as false
@constants::DEFAULTS[:notify_enabled]
#=> false

## DEFAULTS[:default_ttl] preserved as nil (no default TTL)
@constants::DEFAULTS[:default_ttl]
#=> nil

## [forward] runtime defaults reader exists on BrandSettingsConstants
@constants.respond_to?(:defaults)
#=> true

## [forward] BrandSettingsConstants.defaults returns a Hash
@constants.defaults.is_a?(Hash)
#=> true

## [forward] runtime defaults primary_color matches static DEFAULTS by default
# (i.e. when OT.conf has no overriding 'brand' block)
@constants.defaults[:primary_color]
#=> '#3B82F6'

## [forward] runtime defaults are NOT OTS-orange
@constants.defaults[:primary_color] != '#dc4a22'
#=> true

## [forward / regression guard] from_hash with empty input applies neutral blue, NOT OTS-orange
@bs.from_hash({}).primary_color
#=> '#3B82F6'

## [forward] from_hash with empty input applies button_text_light=true (flipped)
@bs.from_hash({}).button_text_light
#=> true

## DEFAULTS exposes only known keys (no surprise additions)
# Sanity check: DEFAULTS keys are a subset of BrandSettings members
extra = @constants::DEFAULTS.keys - @bs.members
extra
#=> []

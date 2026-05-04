# try/unit/models/custom_domain/brand_settings_wcag_try.rb
#
# frozen_string_literal: true

#
# BrandSettings WCAG validators and URL normalization (issue #3048)
#
# Covers validate!, contrast_ratio, relative_luminance, normalize_color,
# valid_url?. All tests are FORWARD-LOOKING — these methods do not exist on
# main yet and arrive with the #3048 backend port.
#

# Pure Ruby validators — no Redis or OT.boot! required.

require 'onetime'
require 'onetime/models/custom_domain'

@bs = Onetime::CustomDomain::BrandSettings

## [forward] normalize_color expands a 3-digit hex to 6-digit (uppercase)
@bs.normalize_color('#abc')
#=> '#AABBCC'

## [forward] normalize_color expands a 3-digit hex with uppercase input
@bs.normalize_color('#ABC')
#=> '#AABBCC'

## [forward] normalize_color upcases a 6-digit hex
@bs.normalize_color('#3b82f6')
#=> '#3B82F6'

## [forward] normalize_color preserves length 7 (#XXXXXX)
@bs.normalize_color('#3B82F6').length
#=> 7

## [forward] normalize_color returns nil for malformed input
@bs.normalize_color('red')
#=> nil

## [forward] normalize_color returns nil for missing hash
@bs.normalize_color('3B82F6')
#=> nil

## [forward] normalize_color returns nil for nil input
@bs.normalize_color(nil)
#=> nil

## [forward] normalize_color returns nil for non-hex chars
@bs.normalize_color('#GGGGGG')
#=> nil

## [forward] relative_luminance for white (#FFFFFF) is 1.0
(@bs.relative_luminance('#FFFFFF') - 1.0).abs < 0.001
#=> true

## [forward] relative_luminance for black (#000000) is 0.0
@bs.relative_luminance('#000000').abs < 0.001
#=> true

## [forward] relative_luminance accepts 3-digit hex (normalized)
(@bs.relative_luminance('#FFF') - 1.0).abs < 0.001
#=> true

## [forward] relative_luminance accepts lowercase
(@bs.relative_luminance('#ffffff') - 1.0).abs < 0.001
#=> true

## [forward] contrast_ratio of black-on-white is 21.0 (WCAG max)
(@bs.contrast_ratio('#000000', '#FFFFFF') - 21.0).abs < 0.01
#=> true

## [forward] contrast_ratio is symmetric (white-on-black == black-on-white)
(@bs.contrast_ratio('#FFFFFF', '#000000') - @bs.contrast_ratio('#000000', '#FFFFFF')).abs < 0.001
#=> true

## [forward] contrast_ratio of white-on-white is 1.0 (WCAG min)
(@bs.contrast_ratio('#FFFFFF', '#FFFFFF') - 1.0).abs < 0.001
#=> true

## [forward] contrast_ratio normalizes 3-digit hex inputs
(@bs.contrast_ratio('#000', '#FFF') - 21.0).abs < 0.01
#=> true

## [forward] contrast_ratio meets WCAG AA (>= 4.5) for black-on-white
@bs.contrast_ratio('#000000', '#FFFFFF') >= 4.5
#=> true

## [forward] valid_url? accepts an https URL
@bs.valid_url?('https://example.com/logo.svg')
#=> true

## [forward] valid_url? rejects an http URL (https-only enforcement)
@bs.valid_url?('http://example.com/logo.svg')
#=> false

## [forward] valid_url? allows a relative path starting with /
@bs.valid_url?('/img/logo.svg')
#=> true

## [forward] valid_url? rejects a URL exceeding 2048 characters
@bs.valid_url?('https://example.com/' + ('a' * 2050))
#=> false

## [forward] valid_url? accepts a URL exactly at the 2048-character cap
@bs.valid_url?('https://example.com/' + ('a' * (2048 - 'https://example.com/'.length)))
#=> true

## [forward] valid_url? rejects nil
@bs.valid_url?(nil)
#=> false

## [forward] valid_url? rejects an empty string
@bs.valid_url?('')
#=> false

## [forward] valid_url? rejects javascript: scheme
@bs.valid_url?('javascript:alert(1)')
#=> false

## [forward] valid_url? rejects data: URIs
@bs.valid_url?('data:image/png;base64,iVBOR')
#=> false

## [forward] valid_url? rejects ftp scheme
@bs.valid_url?('ftp://example.com/file')
#=> false

## [forward] valid_url? rejects malformed URL strings
@bs.valid_url?('not a url at all')
#=> false

## [forward] validate! is a class method on BrandSettings
@bs.respond_to?(:validate!)
#=> true

## [forward] validate! accepts an empty hash without raising (no-op)
begin
  @bs.validate!({})
  'ok'
rescue StandardError
  'raised'
end
#=> 'ok'

## [forward] validate! accepts a valid configuration without raising
begin
  @bs.validate!(primary_color: '#3B82F6', logo_url: 'https://example.com/logo.svg')
  'ok'
rescue StandardError
  'raised'
end
#=> 'ok'

## [forward] validate! raises on a malformed primary_color
begin
  @bs.validate!(primary_color: 'not-a-color')
  'no error'
rescue StandardError
  'raised'
end
#=> 'raised'

## [forward] validate! raises on an http logo_url (https-only)
begin
  @bs.validate!(logo_url: 'http://example.com/logo.svg')
  'no error'
rescue StandardError
  'raised'
end
#=> 'raised'

## [forward] validate! raises on a logo_url over the 2048-character cap
begin
  long = 'https://example.com/' + ('a' * 2050)
  @bs.validate!(logo_url: long)
  'no error'
rescue StandardError
  'raised'
end
#=> 'raised'

## [forward] validate! accepts a relative logo path
begin
  @bs.validate!(logo_url: '/img/logo.svg')
  'ok'
rescue StandardError
  'raised'
end
#=> 'ok'

# ============================================================================
# WCAG 3:1 boundary tests (gap 3 — issue #3048)
# ============================================================================
#
# validate_color_accessibility! enforces a 3:1 minimum contrast ratio against
# white (#FFFFFF). The boundary lives between gray pairs:
#   #949494 -> ratio ~3.03 (passes, just above 3.0)
#   #959595 -> ratio ~2.99 (fails, just below 3.0)
# These exact pairs guard against silent threshold drift if the contrast
# formula or coefficient set ever changes.

## boundary: #949494 against white has contrast ratio ~3.03 (just above 3:1)
ratio = @bs.contrast_ratio('#949494', '#FFFFFF')
ratio > 3.0 && ratio < 3.05
#=> true

## boundary: #959595 against white has contrast ratio ~2.99 (just below 3:1)
ratio = @bs.contrast_ratio('#959595', '#FFFFFF')
ratio < 3.0 && ratio > 2.95
#=> true

## boundary: validate! ACCEPTS #949494 primary_color (passes 3:1 minimum)
begin
  @bs.validate!(primary_color: '#949494')
  'ok'
rescue StandardError
  'raised'
end
#=> 'ok'

## boundary: validate! REJECTS #959595 primary_color (fails 3:1 minimum)
begin
  @bs.validate!(primary_color: '#959595')
  'no error'
rescue StandardError
  'raised'
end
#=> 'raised'

## boundary: error message names accessibility on rejection
begin
  @bs.validate!(primary_color: '#959595')
  ''
rescue Onetime::Problem => e
  e.message.include?('WCAG') || e.message.include?('contrast') || e.message.include?('accessibility')
end
#=> true

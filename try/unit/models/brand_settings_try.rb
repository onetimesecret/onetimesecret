# try/unit/models/brand_settings_try.rb
#
# frozen_string_literal: true

# Tests for Onetime::CustomDomain::BrandSettings Data class
# This is a pure Ruby Data class - no Redis connection required

require 'onetime'
require 'onetime/models/custom_domain'

@bs = Onetime::CustomDomain::BrandSettings

## BrandSettings is a Data class
@bs.ancestors.include?(Data)
#=> true

## BrandSettings defines expected members
@bs.members.sort
#=> [:allow_public_api, :allow_public_homepage, :button_text_light, :corner_style, :font_family, :instructions_post_reveal, :instructions_pre_reveal, :instructions_reveal, :locale, :logo, :primary_color]

## DEFAULTS constant is accessible and frozen
[@bs::DEFAULTS.frozen?, @bs::DEFAULTS[:font_family]]
#=> [true, 'sans']

## FONTS constant contains valid font families
@bs::FONTS
#=> ['sans', 'serif', 'mono']

## CORNERS constant contains valid corner styles
@bs::CORNERS
#=> ['rounded', 'square', 'pill']

## from_hash creates instance with defaults
@settings = @bs.from_hash({})
[@settings.font_family, @settings.corner_style, @settings.primary_color]
#=> ['sans', 'rounded', '#dc4a22']

## from_hash applies custom values
@custom = @bs.from_hash(primary_color: '#FF0000', font_family: 'serif')
[@custom.primary_color, @custom.font_family]
#=> ['#FF0000', 'serif']

## from_hash handles string keys
@string_keys = @bs.from_hash('primary_color' => '#00FF00')
@string_keys.primary_color
#=> '#00FF00'

## from_hash ignores invalid keys
@filtered = @bs.from_hash(invalid_key: 'ignored', font_family: 'mono')
[@filtered.font_family, @filtered.respond_to?(:invalid_key)]
#=> ['mono', false]

## from_hash handles nil input
@nil_input = @bs.from_hash(nil)
@nil_input.font_family
#=> 'sans'

## Instances are frozen (immutable)
@immutable = @bs.from_hash({})
@immutable.frozen?
#=> true

## valid_color? accepts 6-digit hex colors
[@bs.valid_color?('#FF0000'), @bs.valid_color?('#dc4a22'), @bs.valid_color?('#123ABC')]
#=> [true, true, true]

## valid_color? accepts 3-digit hex colors
[@bs.valid_color?('#F00'), @bs.valid_color?('#abc')]
#=> [true, true]

## valid_color? rejects invalid colors
[@bs.valid_color?('FF0000'), @bs.valid_color?('#GGGGGG'), @bs.valid_color?('red'), @bs.valid_color?(nil)]
#=> [false, false, false, false]

## valid_font? accepts valid fonts (case-insensitive)
[@bs.valid_font?('sans'), @bs.valid_font?('SERIF'), @bs.valid_font?('Mono')]
#=> [true, true, true]

## valid_font? rejects invalid fonts
[@bs.valid_font?('comic-sans'), @bs.valid_font?(''), @bs.valid_font?(nil)]
#=> [false, false, false]

## valid_corner_style? accepts valid styles (case-insensitive)
[@bs.valid_corner_style?('rounded'), @bs.valid_corner_style?('SQUARE'), @bs.valid_corner_style?('Pill')]
#=> [true, true, true]

## valid_corner_style? rejects invalid styles
[@bs.valid_corner_style?('circular'), @bs.valid_corner_style?(''), @bs.valid_corner_style?(nil)]
#=> [false, false, false]

## allow_public_homepage? handles various truthy values
[@bs.from_hash(allow_public_homepage: 'true').allow_public_homepage?,
 @bs.from_hash(allow_public_homepage: true).allow_public_homepage?,
 @bs.from_hash(allow_public_homepage: 'false').allow_public_homepage?,
 @bs.from_hash({}).allow_public_homepage?]
#=> [true, true, false, false]

## allow_public_api? handles various truthy values
[@bs.from_hash(allow_public_api: 'true').allow_public_api?,
 @bs.from_hash(allow_public_api: true).allow_public_api?,
 @bs.from_hash(allow_public_api: 'false').allow_public_api?,
 @bs.from_hash({}).allow_public_api?]
#=> [true, true, false, false]

## to_h_for_storage returns hash with string keys
@storage = @bs.from_hash(primary_color: '#FF0000').to_h_for_storage
@storage.keys.first.class
#=> String

## to_h_for_storage JSON-encodes string values
@storage['primary_color']
#=> '"#FF0000"'

## to_h_for_storage JSON-encodes boolean values
@bool_storage = @bs.from_hash(allow_public_api: true).to_h_for_storage
@bool_storage['allow_public_api']
#=> 'true'

## to_h_for_storage excludes nil values
@compact_storage = @bs.from_hash(font_family: 'mono').to_h_for_storage
@compact_storage.key?('logo')
#=> false

## Pattern matching works with BrandSettings
@pattern_test = @bs.from_hash(primary_color: '#FF0000', font_family: 'serif')
result = case @pattern_test
         in { font_family: 'serif' }
           'matched serif'
         else
           'no match'
         end
result
#=> 'matched serif'

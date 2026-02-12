# try/unit/models/brand_settings_wcag_try.rb
#
# frozen_string_literal: true

# Tests for WCAG 2.1 contrast validation in BrandSettings.
# Validates that color accessibility checks work correctly.

require_relative '../../support/test_helpers'

OT.boot! :test, false

@bs = Onetime::CustomDomain::BrandSettings

## contrast_ratio calculates correctly for black and white
ratio = @bs.contrast_ratio('#000000', '#FFFFFF')
ratio.round(2)
#=> 21.0

## contrast_ratio is symmetric (order doesn't matter)
ratio1 = @bs.contrast_ratio('#FF0000', '#FFFFFF')
ratio2 = @bs.contrast_ratio('#FFFFFF', '#FF0000')
((ratio1 - ratio2).abs < 0.01)
#=> true

## contrast_ratio for identical colors is 1.0
@bs.contrast_ratio('#FF0000', '#FF0000').round(2)
#=> 1.0

## relative_luminance returns 0.0 for black
@bs.relative_luminance('#000000')
#=> 0.0

## relative_luminance returns 1.0 for white
@bs.relative_luminance('#FFFFFF')
#=> 1.0

## relative_luminance handles 3-digit hex colors
l1 = @bs.relative_luminance('#F00')
l2 = @bs.relative_luminance('#FF0000')
((l1 - l2).abs < 0.001)
#=> true

## OTS orange (#dc4a22) contrast with white
@bs.contrast_ratio('#dc4a22', '#FFFFFF').round(2)
#=> 4.16

## OTS orange (#dc4a22) contrast with black
@bs.contrast_ratio('#dc4a22', '#000000').round(2)
#=> 5.05

## Navy blue (#000080) has high contrast with white
(@bs.contrast_ratio('#000080', '#FFFFFF') > 15.0)
#=> true

## Light colors have low contrast with white
(@bs.contrast_ratio('#F0F0F0', '#FFFFFF') < 2.0)
#=> true

## validate! accepts colors with sufficient contrast (dark navy)
begin
  @bs.validate!(primary_color: '#000080')
  true
rescue Onetime::Problem
  false
end
#=> true

## validate! accepts colors with sufficient contrast (OTS orange - large text)
begin
  @bs.validate!(primary_color: '#dc4a22')
  true
rescue Onetime::Problem
  false
end
#=> true

## validate! accepts very dark colors (black passes with white)
begin
  @bs.validate!(primary_color: '#000000')
  true
rescue Onetime::Problem
  false
end
#=> true

## validate! rejects very light colors (insufficient contrast)
begin
  @bs.validate!(primary_color: '#F0F0F0')
  false
rescue Onetime::Problem => ex
  ex.message.include?('WCAG AA accessibility')
end
#=> true

## validate! rejects light gray (1.2:1 contrast)
begin
  @bs.validate!(primary_color: '#E0E0E0')
  false
rescue Onetime::Problem => ex
  ex.message.include?('contrast') && ex.message.include?('minimum 3:1')
end
#=> true

## validate! error message includes contrast ratio
begin
  @bs.validate!(primary_color: '#EEEEEE')
  nil
rescue Onetime::Problem => ex
  ex.message.match?(/contrast \d+\.\d+:1/)
end
#=> true

## validate! error message suggests remediation
begin
  @bs.validate!(primary_color: '#F5F5F5')
  nil
rescue Onetime::Problem => ex
  ex.message.include?('darker shade') || ex.message.include?('contrast checker')
end
#=> true

## validate! skips accessibility check when primary_color is nil
begin
  @bs.validate!(font_family: 'sans')
  true
rescue Onetime::Problem
  false
end
#=> true

## validate! skips accessibility check when primary_color key is missing
begin
  @bs.validate!(corner_style: 'rounded')
  true
rescue Onetime::Problem
  false
end
#=> true

## Edge case: Pure red (#FF0000) passes (4.0:1 with white)
begin
  @bs.validate!(primary_color: '#FF0000')
  true
rescue Onetime::Problem
  false
end
#=> true

## Edge case: Medium gray (#808080) passes (3.9:1 with white)
begin
  @bs.validate!(primary_color: '#808080')
  true
rescue Onetime::Problem
  false
end
#=> true

## Edge case: Light blue (#87CEEB) fails (1.6:1 with white)
begin
  @bs.validate!(primary_color: '#87CEEB')
  false
rescue Onetime::Problem => ex
  ex.message.include?('WCAG AA accessibility')
end
#=> true

## validate! requires good contrast with white background specifically
# Dark gray (#333333) has excellent contrast with white (12.6:1)
begin
  @bs.validate!(primary_color: '#333333')
  true
rescue Onetime::Problem
  false
end
#=> true

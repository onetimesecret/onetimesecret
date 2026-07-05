# try/unit/config/config_serializer_brand_color_try.rb
#
# frozen_string_literal: true

# Verifies that brand_primary_color flows through ConfigSerializer
# as nil when BRAND_PRIMARY_COLOR is unset, and as the actual value
# when set. The frontend fallback chain owns the default (#3381).

ENV['AUTHENTICATION_MODE'] = 'full'

require 'rack/request'
require 'rack/mock'

require_relative '../../support/test_helpers'

require 'onetime'
require_relative '../../../apps/web/core/views'

OT.boot! :test, false

def minimal_view_vars(overrides = {})
  {
    'site' => OT.conf.fetch('site', {}),
    'features' => OT.conf.fetch('features', {}),
    'development' => OT.conf.fetch('development', {}),
    'diagnostics' => OT.conf.fetch('diagnostics', {}),
    'homepage_mode' => 'default',
    'display_domain' => 'localhost',
    'brand_primary_color' => nil,
    'brand_product_name' => nil,
    'brand_product_domain' => nil,
    'brand_support_email' => nil,
    'brand_corner_style' => 'rounded',
    'brand_font_family' => 'sans',
    'brand_button_text_light' => false,
    'brand_logo_url' => nil,
    'brand_logo_alt' => nil,
    'brand_favicon_url' => nil,
    'support_email' => nil,
    'docs_host' => 'https://docs.onetimesecret.com/',
  }.merge(overrides)
end

## brand_primary_color is nil when unset
result = Core::Views::ConfigSerializer.serialize(minimal_view_vars)
result['brand_primary_color']
#=> nil

## brand_primary_color passes through explicit hex value
result = Core::Views::ConfigSerializer.serialize(
  minimal_view_vars('brand_primary_color' => '#E11D48')
)
result['brand_primary_color']
#=> "#E11D48"

## brand_primary_color passes through neutral hex without substitution
result = Core::Views::ConfigSerializer.serialize(
  minimal_view_vars('brand_primary_color' => '#3B82F6')
)
result['brand_primary_color']
#=> "#3B82F6"

## output_template defaults brand_primary_color to nil
Core::Views::ConfigSerializer.send(:output_template)['brand_primary_color']
#=> nil

## output_template includes brand_logo_alt defaulting to nil (#3612)
template = Core::Views::ConfigSerializer.send(:output_template)
[template.key?('brand_logo_alt'), template['brand_logo_alt']]
#=> [true, nil]

## brand_logo_alt passes through from view_vars to output
result = Core::Views::ConfigSerializer.serialize(
  minimal_view_vars('brand_logo_alt' => 'Acme wordmark')
)
result['brand_logo_alt']
#=> "Acme wordmark"

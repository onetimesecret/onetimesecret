# try/unit/models/custom_domain/brand_settings_try.rb
#
# frozen_string_literal: true

#
# BrandSettings 22-field Data class structure (issue #3048)
#
# Covers the post-port shape: 14 existing fields + 8 new fields
# (product_name, product_domain, support_email, footer_text, description,
# logo_url, logo_dark_url, favicon_url) plus default semantics, frozen-data
# guarantees, and from_hash behavior.
#
# Most tests below are FORWARD-LOOKING: they will fail until the backend port
# in #3048 lands. Tests are marked with [forward] for clarity.
#

# Pure Ruby Data class — no Redis or OT.boot! required.

require 'onetime'
require 'onetime/models/custom_domain'

@bs = Onetime::CustomDomain::BrandSettings

## BrandSettings is a Data class (preserved from main)
@bs.ancestors.include?(Data)
#=> true

## [forward] BrandSettings defines all 22 expected members
@bs.members.sort
#=> [:allow_public_api, :allow_public_homepage, :button_text_light, :corner_style, :default_ttl, :description, :favicon_url, :font_family, :footer_text, :instructions_post_reveal, :instructions_pre_reveal, :instructions_reveal, :locale, :logo, :logo_dark_url, :logo_url, :notify_enabled, :passphrase_required, :primary_color, :product_domain, :product_name, :support_email]

## [forward] BrandSettings has exactly 22 members
@bs.members.size
#=> 22

## [forward] from_hash creates instance with new product_name field
@settings = @bs.from_hash({})
@settings.respond_to?(:product_name)
#=> true

## [forward] from_hash creates instance with new product_domain field
@bs.from_hash({}).respond_to?(:product_domain)
#=> true

## [forward] from_hash creates instance with new support_email field
@bs.from_hash({}).respond_to?(:support_email)
#=> true

## [forward] from_hash creates instance with new footer_text field
@bs.from_hash({}).respond_to?(:footer_text)
#=> true

## [forward] from_hash creates instance with new description field
@bs.from_hash({}).respond_to?(:description)
#=> true

## [forward] from_hash creates instance with new logo_url field
@bs.from_hash({}).respond_to?(:logo_url)
#=> true

## [forward] from_hash creates instance with new logo_dark_url field
@bs.from_hash({}).respond_to?(:logo_dark_url)
#=> true

## [forward] from_hash creates instance with new favicon_url field
@bs.from_hash({}).respond_to?(:favicon_url)
#=> true

## [forward] from_hash sets new fields from input hash (string keys)
@populated = @bs.from_hash(
  'product_name' => 'Acme',
  'product_domain' => 'acme.test',
  'support_email' => 'help@acme.test',
  'footer_text' => 'Acme Inc.',
  'description' => 'Secure secrets',
  'logo_url' => 'https://acme.test/logo.svg',
  'logo_dark_url' => 'https://acme.test/logo-dark.svg',
  'favicon_url' => 'https://acme.test/favicon.ico',
)
[@populated.product_name, @populated.product_domain, @populated.support_email, @populated.logo_url]
#=> ['Acme', 'acme.test', 'help@acme.test', 'https://acme.test/logo.svg']

## [forward] from_hash sets new fields from input hash (symbol keys)
@sym = @bs.from_hash(
  product_name: 'Acme',
  footer_text: 'Footer',
  description: 'Desc',
  logo_dark_url: 'https://x.test/d.svg',
  favicon_url: 'https://x.test/f.ico',
)
[@sym.product_name, @sym.footer_text, @sym.description, @sym.logo_dark_url, @sym.favicon_url]
#=> ['Acme', 'Footer', 'Desc', 'https://x.test/d.svg', 'https://x.test/f.ico']

## [forward] new fields default to nil (or DEFAULTS value if specified) when omitted
@empty = @bs.from_hash({})
[@empty.product_domain, @empty.footer_text, @empty.description, @empty.logo_url, @empty.logo_dark_url, @empty.favicon_url]
#=> [nil, nil, nil, nil, nil, nil]

## [forward] button_text_light default is now true (flipped from false)
@bs.from_hash({}).button_text_light
#=> true

## from_hash preserves existing 14-field behavior — corner_style default
@bs.from_hash({}).corner_style
#=> 'rounded'

## from_hash preserves existing 14-field behavior — font_family default
@bs.from_hash({}).font_family
#=> 'sans'

## from_hash preserves existing 14-field behavior — locale default
@bs.from_hash({}).locale
#=> 'en'

## Instances are frozen (Data semantics, preserved)
@bs.from_hash({}).frozen?
#=> true

## Instances cannot be mutated via setter (Data semantics)
@instance = @bs.from_hash({})
begin
  @instance.instance_variable_set(:@primary_color, '#000000')
  'mutated'
rescue FrozenError
  'frozen'
end
#=> 'frozen'

## from_hash ignores unknown keys (preserved)
@filtered = @bs.from_hash(invalid_key: 'ignored', font_family: 'mono')
[@filtered.font_family, @filtered.respond_to?(:invalid_key)]
#=> ['mono', false]

## from_hash handles nil input (preserved)
@bs.from_hash(nil).font_family
#=> 'sans'

## DEFAULTS constant is accessible and frozen (preserved)
@bs::DEFAULTS.frozen?
#=> true

## FONTS constant unchanged
@bs::FONTS
#=> ['sans', 'serif', 'mono']

## CORNERS constant unchanged
@bs::CORNERS
#=> ['rounded', 'square', 'pill']

## Pattern matching works with new fields
@pattern = @bs.from_hash(product_name: 'Acme')
result = case @pattern
         in { product_name: 'Acme' }
           'matched'
         else
           'no match'
         end
result
#=> 'matched'

## [forward] to_h_for_storage handles new string fields (JSON-encoded)
@storage = @bs.from_hash(product_name: 'Acme', support_email: 'help@acme.test').to_h_for_storage
[@storage['product_name'], @storage['support_email']]
#=> ['"Acme"', '"help@acme.test"']

## to_h_for_storage excludes nil values (preserved)
@bs.from_hash({}).to_h_for_storage.key?('logo_url')
#=> false

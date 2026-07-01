# try/web/core/logic/page/get_webmanifest_try.rb
#
# frozen_string_literal: true

# Tests for Core::Logic::Page::GetWebmanifest.
#
# The /site.webmanifest route serves a brand-aware PWA manifest: it reads the
# on-disk neutral manifest and overlays brand.product_name / brand.primary_color
# from OT.conf. With no brand config it serves the neutral default unchanged, so
# a self-hosted install never ships OTS branding in its manifest.
#
# Behaviours covered:
# 1. Neutral default name ("Secure Links") + neutral theme colour when brand absent.
# 2. brand.product_name overrides name and short_name.
# 3. brand.primary_color overrides theme_color.
# 4. content_type is application/manifest+json.
# 5. [regression guard] neutral default name is never OTS-branded.

require 'json'
require_relative '../../../../../try/support/test_helpers'
require_relative '../../../../../try/support/test_models'

OT.boot! :test, false

require 'web/core/logic/page/get_webmanifest'

@orig_brand = OT.conf['brand']

# Builds the logic with the CURRENT OT.conf['brand'] (process_params runs in the
# constructor, so brand config must be set before calling this).
def build_logic
  sess = MockSession.new
  strategy_result = MockStrategyResult.new(
    session: sess,
    user: nil,
    auth_method: 'anonymous',
    metadata: {}
  )
  logic = Core::Logic::Page::GetWebmanifest.new(strategy_result, {}, 'en')
  logic.raise_concerns
  logic.process
  logic
end

## Neutral default: name is the bundled "Secure Links", theme is neutral blue, correct content-type
OT.conf['brand'] = {}
logic = build_logic
m = JSON.parse(logic.manifest_json)
[m['name'], m['theme_color'], logic.content_type]
#=> ['Secure Links', '#3B82F6', 'application/manifest+json']

## brand.product_name overrides name and short_name
OT.conf['brand'] = { 'product_name' => 'Acme Vault' }
m = JSON.parse(build_logic.manifest_json)
[m['name'], m['short_name']]
#=> ['Acme Vault', 'Acme Vault']

## brand.primary_color overrides theme_color
OT.conf['brand'] = { 'primary_color' => '#112233' }
JSON.parse(build_logic.manifest_json)['theme_color']
#=> '#112233'

## blank brand values do not clobber the neutral defaults
OT.conf['brand'] = { 'product_name' => '', 'primary_color' => '  ' }
m = JSON.parse(build_logic.manifest_json)
[m['name'], m['theme_color']]
#=> ['Secure Links', '#3B82F6']

## [regression guard] neutral default manifest name is never OTS-branded
OT.conf['brand'] = {}
name = JSON.parse(build_logic.manifest_json)['name'].downcase
[name.include?('onetime'), name.include?('one-time')]
#=> [false, false]

# Teardown
OT.conf['brand'] = @orig_brand

# try/unit/web/favicon_variety_pack_try.rb
#
# frozen_string_literal: true

#
# Favicon + mobile/social variety pack (v0.26)
#
# Two concerns:
#
# 1. apps/web/core/views/helpers/initialize_view_vars.rb resolves the head's
#    variety-pack URLs (apple-touch-icon, og:image) from OT.conf['brand'],
#    falling back to the bundled NEUTRAL default paths when unset.
#
# 2. [trust regression guard] The OSS repo must ship a brand-NEUTRAL default
#    pack (public/branding/default, #3774). Shipping the onetimesecret.com
#    (#DC4A22) favicon / social pack as the default would mean every self-hosted
#    install serves our company brand — the exact hazard #3048/#3049 neutralized
#    for colours and this change neutralizes for the static icon files.
#

require 'json'
require_relative '../../support/test_helpers'

require 'rack/request'
require 'rack/mock'
require 'onetime'
require_relative '../../../apps/web/core/views/helpers/initialize_view_vars'

OT.boot! :test, false

@host = Object.new
@host.extend(Core::Views::InitializeViewVars)

def build_env(display_domain: nil)
  env                            = Rack::MockRequest.env_for('http://example.com/')
  env['otto.locale']             = 'en'
  env['onetime.nonce']           = 'test-nonce'
  env['onetime.display_domain']  = display_domain
  env['onetime.domain_strategy'] = :default
  env['rack.session']            = {}
  env
end

def with_brand_conf(brand_hash)
  saved     = YAML.load(YAML.dump(OT.conf))
  conf_copy = YAML.load(YAML.dump(saved))
  if brand_hash.nil?
    conf_copy.delete('brand')
  else
    conf_copy['brand'] = brand_hash
  end
  OT.send(:conf=, conf_copy)
  yield
ensure
  OT.send(:conf=, saved) rescue nil
end

# The neutral variety pack now lives in the tracked DEFAULT brand pack (#3774),
# not loose files in public/web.
PUBLIC_WEB = File.expand_path('../../../public/branding/default', __dir__)

# TRYOUTS

# ============================================================================
# View-var resolution (override vs neutral default)
# ============================================================================

## brand_apple_touch_icon_url defaults to the neutral bundled path when brand absent
with_brand_conf(nil) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['brand_apple_touch_icon_url']
end
#=> '/apple-touch-icon.png'

## brand_apple_touch_icon_url reflects BRAND_APPLE_TOUCH_ICON_URL override when set
with_brand_conf({ 'apple_touch_icon_url' => 'https://cdn.acme.test/touch.png' }) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['brand_apple_touch_icon_url']
end
#=> 'https://cdn.acme.test/touch.png'

## brand_og_image_url default is an absolute URL ending in the neutral social card
with_brand_conf(nil) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  u = vars['brand_og_image_url']
  [u.start_with?('http://', 'https://'), u.end_with?('/social-preview.png')]
end
#=> [true, true]

## brand_og_image_url reflects BRAND_OG_IMAGE_URL override when set
with_brand_conf({ 'og_image_url' => 'https://cdn.acme.test/card.png' }) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['brand_og_image_url']
end
#=> 'https://cdn.acme.test/card.png'

## both variety-pack keys are exposed by initialize_view_vars
vars = @host.initialize_view_vars(Rack::Request.new(build_env))
[vars.key?('brand_apple_touch_icon_url'), vars.key?('brand_og_image_url')]
#=> [true, true]

# ============================================================================
# SVG favicon precedence gate (must not shadow per-domain / brand favicon)
# ============================================================================

## default (canonical) install with no brand favicon emits the crisp SVG favicon
with_brand_conf(nil) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['show_default_svg_favicon']
end
#=> true

## a brand.favicon_url install suppresses the static SVG (the /favicon.ico redirect wins)
with_brand_conf({ 'favicon_url' => 'https://cdn.acme.test/favicon.ico' }) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['show_default_svg_favicon']
end
#=> false

## [regression guard] a custom domain suppresses the static SVG so its uploaded /favicon.ico is not shadowed
def build_custom_env
  env = build_env
  env['onetime.domain_strategy'] = :custom
  env
end
with_brand_conf(nil) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_custom_env))
  vars['show_default_svg_favicon']
end
#=> false

# ============================================================================
# [trust regression guard] shipped defaults are brand-NEUTRAL
# ============================================================================

## the full variety pack ships in the tracked default pack
%w[
  favicon.ico favicon.svg apple-touch-icon.png icon-192.png icon-512.png
  safari-pinned-tab.svg site.webmanifest social-preview.png
].all? { |f| File.exist?(File.join(PUBLIC_WEB, f)) }
#=> true

## favicon.svg uses the neutral blue, not the OTS orange (#DC4A22)
svg = File.read(File.join(PUBLIC_WEB, 'favicon.svg'))
[svg.include?('#3B82F6'), svg.downcase.include?('#dc4a22')]
#=> [true, false]

## site.webmanifest ships a neutral theme colour
JSON.parse(File.read(File.join(PUBLIC_WEB, 'site.webmanifest')))['theme_color']
#=> '#3B82F6'

## [regression guard] manifest name is neutral, not OTS-branded
name = JSON.parse(File.read(File.join(PUBLIC_WEB, 'site.webmanifest')))['name'].downcase
[name.include?('onetime'), name.include?('one-time')]
#=> [false, false]

## safari-pinned-tab.svg ships (head references it) and is monochrome black
mask = File.read(File.join(PUBLIC_WEB, 'safari-pinned-tab.svg'))
[mask.include?('#000000'), mask.downcase.include?('#dc4a22')]
#=> [true, false]

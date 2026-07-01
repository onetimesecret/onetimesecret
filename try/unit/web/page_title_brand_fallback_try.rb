# try/unit/web/page_title_brand_fallback_try.rb
#
# frozen_string_literal: true

#
# page_title brand fallback chain (issue #3048 / #3049)
#
# Covers Task 5: apps/web/core/views/helpers/initialize_view_vars.rb.
# Specifically the page_title fallback chain change: the helper must
# resolve page_title via the brand-aware chain
#
#   display_domain (request) -> brand_product_name -> site_name (deprecated)
#
# and NEVER hardcode 'Onetime Secret' so that private-label / self-hosted
# instances don't ship OTS branding by accident.
#
# Also asserts the 9 brand_* / brand-adjacent view vars exposed by the
# helper are present with expected types.
#
# Most assertions are already passing as of Wave 1 commit 666cb3a05; the
# bullets that depend on backend-dev's not-yet-landed work (e.g. removing
# any residual hardcoded 'Onetime Secret') are forward-looking.
#

require_relative '../../support/test_helpers'

require 'rack/request'
require 'rack/mock'
require 'onetime'
require_relative '../../../apps/web/core/views/helpers/initialize_view_vars'

# Boot the test environment so OT.conf is populated.
OT.boot! :test, false

# Snapshot config for restoring after each mutating test.
@_saved_conf = YAML.load(YAML.dump(OT.conf))

# Bare object that extends the helper, since InitializeViewVars is meant
# to be `extend`ed onto a view class. This gives us a host for the
# initialize_view_vars method without dragging the whole VuePoint stack.
@host = Object.new
@host.extend(Core::Views::InitializeViewVars)

# Build a minimal Rack env with the bits initialize_view_vars reads.
def build_env(display_domain: nil)
  env                              = Rack::MockRequest.env_for('http://example.com/')
  env['otto.locale']               = 'en'
  env['onetime.nonce']             = 'test-nonce'
  env['onetime.display_domain']    = display_domain
  env['onetime.domain_strategy']   = :default
  env['rack.session']              = {}
  env
end

# Run a block with OT.conf['brand'] set to brand_hash (or removed when nil).
# Restores the original OT.conf in an ensure block.
def with_brand_conf(brand_hash)
  saved = YAML.load(YAML.dump(OT.conf))
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

# TRYOUTS

# ============================================================================
# page_title fallback chain
# ============================================================================

## page_title falls through to brand_product_name when brand config is set
with_brand_conf({ 'product_name' => 'Acme Vault' }) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['page_title']
end
#=> 'Acme Vault'

## page_title prefers display_domain over brand_product_name when present
with_brand_conf({ 'product_name' => 'Acme Vault' }) do
  req = Rack::Request.new(build_env(display_domain: 'vault.acme.test'))
  vars = @host.initialize_view_vars(req)
  vars['page_title']
end
#=> 'vault.acme.test'

# GLOBAL_DEFAULTS[:product_name] is nil per #3049, so this exercises the
# shipped config.defaults.yaml site.interface.ui.header.branding.site_name
# default rather than a brand-layer value.
## page_title falls through to the legacy site_name when brand absent
with_brand_conf(nil) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['page_title']
end
#=> 'One-Time Secret'

## page_title falls through to GLOBAL_DEFAULTS[:product_name] (nil) when brand and legacy site_name are both absent
with_brand_conf(nil) do
  saved = YAML.load(YAML.dump(OT.conf))
  begin
    conf_copy = YAML.load(YAML.dump(OT.conf))
    conf_copy.dig('site', 'interface', 'ui', 'header', 'branding')&.delete('site_name')
    OT.send(:conf=, conf_copy)
    vars = @host.initialize_view_vars(Rack::Request.new(build_env))
    vars['page_title']
  ensure
    OT.send(:conf=, saved) rescue nil
  end
end
#=> nil

## [regression guard] page_title NEVER returns hardcoded 'Onetime Secret' when brand absent
with_brand_conf(nil) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['page_title'] != 'Onetime Secret'
end
#=> true

## [regression guard] GLOBAL_DEFAULTS[:product_name] is nil, not 'OTS' or 'Onetime Secret'
Onetime::CustomDomain::BrandSettingsConstants::GLOBAL_DEFAULTS[:product_name]
#=> nil

# ============================================================================
# 9 brand_* / brand-adjacent view var keys exist
# ============================================================================

## initialize_view_vars exposes 'brand_primary_color'
vars = @host.initialize_view_vars(Rack::Request.new(build_env))
vars.key?('brand_primary_color')
#=> true

## brand_primary_color is a String hex color when brand primary_color is set
with_brand_conf({ 'primary_color' => '#112233' }) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  [vars['brand_primary_color'].is_a?(String), vars['brand_primary_color'].start_with?('#')]
end
#=> [true, true]

## [regression guard] brand_primary_color is nil when brand absent — backend no longer backfills, frontend fallback chain owns the default (#3381)
with_brand_conf(nil) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['brand_primary_color']
end
#=> nil

## initialize_view_vars exposes 'brand_product_name'
vars = @host.initialize_view_vars(Rack::Request.new(build_env))
vars.key?('brand_product_name')
#=> true

## brand_product_name is nil when unset — frontend NEUTRAL_BRAND_DEFAULTS owns the default (#3049)
vars = @host.initialize_view_vars(Rack::Request.new(build_env))
vars['brand_product_name']
#=> nil

## brand_product_name is a String once BRAND_PRODUCT_NAME / brand.product_name is configured
with_brand_conf({ 'product_name' => 'Acme Vault' }) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['brand_product_name'].is_a?(String)
end
#=> true

## initialize_view_vars exposes 'brand_corner_style'
vars = @host.initialize_view_vars(Rack::Request.new(build_env))
vars.key?('brand_corner_style')
#=> true

## brand_corner_style default is 'rounded'
with_brand_conf(nil) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['brand_corner_style']
end
#=> 'rounded'

## initialize_view_vars exposes 'brand_font_family'
vars = @host.initialize_view_vars(Rack::Request.new(build_env))
vars.key?('brand_font_family')
#=> true

## brand_font_family default is 'sans'
with_brand_conf(nil) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['brand_font_family']
end
#=> 'sans'

## initialize_view_vars exposes 'brand_button_text_light'
vars = @host.initialize_view_vars(Rack::Request.new(build_env))
vars.key?('brand_button_text_light')
#=> true

## brand_button_text_light default is true (flipped per #3048)
with_brand_conf(nil) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['brand_button_text_light']
end
#=> true

## initialize_view_vars exposes 'brand_allow_public_homepage'
vars = @host.initialize_view_vars(Rack::Request.new(build_env))
vars.key?('brand_allow_public_homepage')
#=> true

## brand_allow_public_homepage default is false
with_brand_conf(nil) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['brand_allow_public_homepage']
end
#=> false

## initialize_view_vars exposes 'brand_allow_public_api'
vars = @host.initialize_view_vars(Rack::Request.new(build_env))
vars.key?('brand_allow_public_api')
#=> true

## brand_allow_public_api default is false
with_brand_conf(nil) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['brand_allow_public_api']
end
#=> false

## initialize_view_vars exposes 'support_email'
vars = @host.initialize_view_vars(Rack::Request.new(build_env))
vars.key?('support_email')
#=> true

## support_email defaults to GLOBAL_DEFAULTS[:support_email] when brand absent (nil per #3049)
with_brand_conf(nil) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['support_email']
end
#=> nil

## [regression guard] support_email is NOT 'support@onetimesecret.com' when brand absent
with_brand_conf(nil) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['support_email'] != 'support@onetimesecret.com'
end
#=> true

## support_email reflects OT.conf['brand']['support_email'] when set
with_brand_conf({ 'support_email' => 'help@acme.test' }) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['support_email']
end
#=> 'help@acme.test'

## initialize_view_vars exposes 'docs_host'
vars = @host.initialize_view_vars(Rack::Request.new(build_env))
vars.key?('docs_host')
#=> true

## docs_host is a non-empty String (sourced from DOCS_URL env or its default)
vars = @host.initialize_view_vars(Rack::Request.new(build_env))
vars['docs_host'].is_a?(String) && !vars['docs_host'].empty?
#=> true

## docs_host reflects DOCS_URL env var when set
ENV['DOCS_URL'] = 'https://docs.acme.test/'
vars = @host.initialize_view_vars(Rack::Request.new(build_env))
result = vars['docs_host']
ENV.delete('DOCS_URL')
result
#=> 'https://docs.acme.test/'

# ============================================================================
# DOCS_URL fallback regression guard (gap 2 — issue #3048)
# ============================================================================
#
# When DOCS_URL is unset, docs_host must resolve to the hardcoded default
# 'https://docs.onetimesecret.com/'. The pair-with-DOCS_URL-set test above
# proves the env override path; this proves the default path so neither
# end of the precedence chain regresses silently.

## docs_host falls back to default when DOCS_URL is unset
@_saved_docs_url = ENV.delete('DOCS_URL')
begin
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['docs_host']
ensure
  ENV['DOCS_URL'] = @_saved_docs_url if @_saved_docs_url
end
#=> 'https://docs.onetimesecret.com/'

## [regression guard] DOCS_URL fallback default is non-empty https URL
@_saved_docs_url2 = ENV.delete('DOCS_URL')
begin
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  result = vars['docs_host']
  result.is_a?(String) && result.start_with?('https://') && !result.empty?
ensure
  ENV['DOCS_URL'] = @_saved_docs_url2 if @_saved_docs_url2
end
#=> true

# ============================================================================
# Sanity: brand_primary_color reflects override when set
# ============================================================================

## brand_primary_color reflects OT.conf['brand']['primary_color'] when set
with_brand_conf({ 'primary_color' => '#112233' }) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['brand_primary_color']
end
#=> '#112233'

## brand_product_name reflects OT.conf['brand']['product_name'] when set
with_brand_conf({ 'product_name' => 'Acme Vault' }) do
  vars = @host.initialize_view_vars(Rack::Request.new(build_env))
  vars['brand_product_name']
end
#=> 'Acme Vault'

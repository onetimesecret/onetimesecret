# try/unit/web/brand_asset_overlay_try.rb
#
# frozen_string_literal: true

#
# Runtime brand-asset overlay (#3739)
#
# Covers the overlay resolver added in lib/onetime.rb plus the three serving
# chokepoints that consume it:
#
#   1. Onetime.brand_overlay_dir  — precedence + path-traversal rejection.
#   2. Onetime.brand_asset_path   — overlay-first single-file resolver with a
#      byte-identical no-overlay fallback (preserves today's behaviour).
#   3. GetFavicon#serve_default_favicon — overlay favicon.ico, neutral
#      fall-through, and BRAND_FAVICON_URL redirect precedence.
#   4. GetWebmanifest#load_base_manifest — overlay base manifest, brand.*
#      overlay on top, public_dir fall-back, and NEUTRAL_FALLBACK on corruption.
#   5. StaticFiles overlay URL existence-filtering — partial overlays list only
#      the files that actually exist (Rack::Static would 404 otherwise).
#
# Overlay config is set on OT.conf['site'] per-test and RESET in teardown so
# later tests (and later files sharing the process) see NO overlay. This must
# not perturb the neutral-default guards in favicon_variety_pack_try /
# get_webmanifest_try.
#

require 'json'
require 'tmpdir'
require 'fileutils'
require_relative '../../support/test_helpers'

OT.boot! :test, false

require 'onetime/middleware/static_files'
require 'web/core/logic/page/get_favicon'
require 'web/core/logic/page/get_webmanifest'

BRAND_PACK_URLS = Onetime::Middleware::StaticFiles::BRAND_PACK_URLS
PUBLIC_WEB      = File.join(Onetime::HOME, 'public', 'web')

OT.conf['site'] ||= {}

# Capture originals so teardown fully restores the no-overlay baseline.
@orig_assets_dir = OT.conf['site']['brand_assets_dir']
@orig_pack       = OT.conf['site']['brand_pack']
@orig_brand      = OT.conf['brand']

# --- Overlay fixtures (absolute temp dirs) --------------------------------

# Overlay containing favicon.ico only.
@overlay_favicon = Dir.mktmpdir('ots-overlay-favicon')
File.binwrite(File.join(@overlay_favicon, 'favicon.ico'), 'OVERLAY-ICO-BYTES')

# Overlay containing a custom site.webmanifest.
@overlay_manifest = Dir.mktmpdir('ots-overlay-manifest')
File.write(
  File.join(@overlay_manifest, 'site.webmanifest'),
  JSON.generate('name' => 'Overlay Pack', 'short_name' => 'Overlay Pack',
                'theme_color' => '#0f0f0f', 'icons' => [])
)

# Overlay containing a CORRUPT site.webmanifest (exercises the rescue path).
@overlay_bad_manifest = Dir.mktmpdir('ots-overlay-badmanifest')
File.write(File.join(@overlay_bad_manifest, 'site.webmanifest'), '{not valid json')

# Overlay that exists but is EMPTY (every asset misses -> fall through).
@overlay_empty = Dir.mktmpdir('ots-overlay-empty')

# Partial overlay: only favicon.svg present.
@overlay_partial = Dir.mktmpdir('ots-overlay-partial')
File.write(File.join(@overlay_partial, 'favicon.svg'), '<svg/>')

# A valid brand_pack dir under public/branding/<name> (name -> dir resolution).
@pack_name = "trytest_#{Process.pid}"
@pack_dir  = File.join(Onetime::HOME, 'public', 'branding', @pack_name)
FileUtils.mkdir_p(@pack_dir)

def set_overlay(assets_dir: nil, pack: nil)
  OT.conf['site']['brand_assets_dir'] = assets_dir
  OT.conf['site']['brand_pack']       = pack
end

def clear_overlay
  OT.conf['site']['brand_assets_dir'] = nil
  OT.conf['site']['brand_pack']       = nil
end

# Default-mode (canonical, no custom domain) GetFavicon run through the pipeline.
def run_default_favicon
  sr = MockStrategyResult.new(
    session: MockSession.new, user: nil, auth_method: 'anonymous',
    metadata: { domain_strategy: :canonical, display_domain: 'example.com' }
  )
  logic = Core::Logic::Page::GetFavicon.new(sr, {}, 'en')
  logic.raise_concerns
  logic.process
  logic
end

# GetWebmanifest run with the CURRENT OT.conf['brand'].
def run_webmanifest
  sr = MockStrategyResult.new(
    session: MockSession.new, user: nil, auth_method: 'anonymous', metadata: {}
  )
  logic = Core::Logic::Page::GetWebmanifest.new(sr, {}, 'en')
  logic.raise_concerns
  logic.process
  logic
end

# TRYOUTS

# ============================================================================
# 1. Onetime.brand_overlay_dir — precedence + security
# ============================================================================

## neither brand_assets_dir nor brand_pack configured -> nil (no overlay)
clear_overlay
Onetime.brand_overlay_dir
#=> nil

## explicit brand_assets_dir WINS over a valid brand_pack
set_overlay(assets_dir: @overlay_favicon, pack: @pack_name)
Onetime.brand_overlay_dir == @overlay_favicon
#=> true

## blank/whitespace brand_assets_dir is skipped, brand_pack resolves
set_overlay(assets_dir: '   ', pack: @pack_name)
Onetime.brand_overlay_dir == @pack_dir
#=> true

## valid brand_pack NAME resolves to public/branding/<name>
set_overlay(assets_dir: nil, pack: @pack_name)
Onetime.brand_overlay_dir == @pack_dir
#=> true

## nonexistent brand_pack dir -> nil
set_overlay(assets_dir: nil, pack: 'definitely_not_a_pack_xyz')
Onetime.brand_overlay_dir
#=> nil

## [security] brand_pack containing '/' is rejected -> nil
set_overlay(assets_dir: nil, pack: 'foo/bar')
Onetime.brand_overlay_dir
#=> nil

## [security] brand_pack containing a backslash is rejected -> nil
set_overlay(assets_dir: nil, pack: 'foo\\bar')
Onetime.brand_overlay_dir
#=> nil

## [security] brand_pack containing '..' traversal is rejected -> nil
set_overlay(assets_dir: nil, pack: '../evil')
Onetime.brand_overlay_dir
#=> nil

## explicit brand_assets_dir that is missing -> nil, does NOT fall through to pack
set_overlay(assets_dir: '/no/such/overlay/dir_xyz', pack: @pack_name)
Onetime.brand_overlay_dir
#=> nil

# ============================================================================
# 2. Onetime.brand_asset_path — overlay-first single-file resolver
# ============================================================================

## overlay hit returns the overlay copy of the file
set_overlay(assets_dir: @overlay_favicon, pack: nil)
Onetime.brand_asset_path('favicon.ico') == File.join(@overlay_favicon, 'favicon.ico')
#=> true

## overlay configured but file absent -> falls through to the public_dir path
set_overlay(assets_dir: @overlay_empty, pack: nil)
expected = File.join(OT.conf.dig('site', 'public_dir') || 'public/web', 'favicon.ico')
Onetime.brand_asset_path('favicon.ico') == expected
#=> true

## no overlay -> byte-identical to the pre-#3739 File.join literal
clear_overlay
expected = File.join(OT.conf.dig('site', 'public_dir') || 'public/web', 'favicon.ico')
Onetime.brand_asset_path('favicon.ico') == expected
#=> true

# ============================================================================
# 3. GetFavicon#serve_default_favicon — overlay / neutral / redirect precedence
# ============================================================================

## overlay favicon.ico is served when present
OT.conf['brand'] = {}
set_overlay(assets_dir: @overlay_favicon, pack: nil)
logic = run_default_favicon
[logic.icon_data, logic.content_type, logic.redirect_url]
#=> ['OVERLAY-ICO-BYTES', 'image/x-icon', nil]

## overlay missing the file falls through to the neutral public/web favicon
OT.conf['brand'] = {}
set_overlay(assets_dir: @overlay_empty, pack: nil)
logic = run_default_favicon
neutral = File.binread(File.join(PUBLIC_WEB, 'favicon.ico'))
[logic.icon_data == neutral, logic.content_type, logic.redirect_url]
#=> [true, 'image/x-icon', nil]

## BRAND_FAVICON_URL https redirect wins over the overlay (higher precedence)
OT.conf['brand'] = { 'favicon_url' => 'https://cdn.acme.test/favicon.ico' }
set_overlay(assets_dir: @overlay_favicon, pack: nil)
logic = run_default_favicon
[logic.redirect_url, logic.icon_data]
#=> ['https://cdn.acme.test/favicon.ico', nil]

# ============================================================================
# 4. GetWebmanifest#load_base_manifest — overlay / brand overlay / fallbacks
# ============================================================================

## base manifest is read from the overlay when present
OT.conf['brand'] = {}
set_overlay(assets_dir: @overlay_manifest, pack: nil)
m = JSON.parse(run_webmanifest.manifest_json)
[m['name'], m['theme_color']]
#=> ['Overlay Pack', '#0f0f0f']

## brand.* fields still overlay on top of the overlay base manifest
OT.conf['brand'] = { 'product_name' => 'Acme Vault', 'primary_color' => '#123456' }
set_overlay(assets_dir: @overlay_manifest, pack: nil)
m = JSON.parse(run_webmanifest.manifest_json)
[m['name'], m['short_name'], m['theme_color']]
#=> ['Acme Vault', 'Acme Vault', '#123456']

## overlay missing site.webmanifest falls back to the neutral public_dir manifest
OT.conf['brand'] = {}
set_overlay(assets_dir: @overlay_empty, pack: nil)
JSON.parse(run_webmanifest.manifest_json)['name']
#=> 'Secure Links'

## corrupt overlay manifest triggers the NEUTRAL_FALLBACK rescue path
OT.conf['brand'] = {}
set_overlay(assets_dir: @overlay_bad_manifest, pack: nil)
m = JSON.parse(run_webmanifest.manifest_json)
[m['name'], m['theme_color'], m['start_url']]
#=> ['Secure Links', '#3B82F6', '/']

# ============================================================================
# 5. StaticFiles overlay URL existence-filtering (partial overlay)
# ============================================================================

## partial overlay: only the file that exists is listed for the overlay layer
set_overlay(assets_dir: @overlay_partial, pack: nil)
overlay_dir = Onetime.brand_overlay_dir
BRAND_PACK_URLS.select { |u| File.exist?(File.join(overlay_dir, u)) }
#=> ['/favicon.svg']

## absent overlay files are excluded (they fall through to the base public/web layer)
set_overlay(assets_dir: @overlay_partial, pack: nil)
overlay_dir = Onetime.brand_overlay_dir
present = BRAND_PACK_URLS.select { |u| File.exist?(File.join(overlay_dir, u)) }
absent  = (BRAND_PACK_URLS - present).sort
[present, absent]
#=> [['/favicon.svg'], ['/apple-touch-icon.png', '/icon-192.png', '/icon-512.png', '/safari-pinned-tab.svg', '/social-preview.png']]

## empty overlay selects no URLs -> middleware skips the overlay layer entirely
set_overlay(assets_dir: @overlay_empty, pack: nil)
overlay_dir = Onetime.brand_overlay_dir
BRAND_PACK_URLS.select { |u| File.exist?(File.join(overlay_dir, u)) }.empty?
#=> true

# Teardown — restore the no-overlay baseline and remove fixtures.
OT.conf['brand']                    = @orig_brand
OT.conf['site']['brand_assets_dir'] = @orig_assets_dir
OT.conf['site']['brand_pack']       = @orig_pack
[@overlay_favicon, @overlay_manifest, @overlay_bad_manifest,
 @overlay_empty, @overlay_partial].each { |d| FileUtils.remove_entry(d) rescue nil }
FileUtils.remove_entry(@pack_dir) rescue nil

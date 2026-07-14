# try/unit/web/brand_asset_overlay_try.rb
#
# frozen_string_literal: true

#
# Brand-pack resolution + runtime asset overlay (#3739, v2 #3774)
#
# Covers the pack resolver in lib/onetime.rb plus the serving chokepoints that
# consume it:
#
#   1. Onetime.brand_pack_dir       — two-root NAME resolution + traversal reject.
#   2. Onetime.resolve_brand_pack_dir / brand_overlay_dir — precedence, and the
#      v2 "resolution always lands on a pack" rule (unset ⇒ the default pack).
#   3. Onetime.brand_asset_path     — overlay-first single-file resolver that now
#      collapses onto the pack path (selected pack → default pack → public/web).
#   4. GetFavicon#serve_default_favicon — overlay favicon.ico, default-pack
#      fall-through, and BRAND_FAVICON_URL redirect precedence.
#   5. GetWebmanifest#load_base_manifest — overlay base manifest, brand.* overlay
#      on top, default-pack fall-back, and NEUTRAL_FALLBACK on corruption.
#   6. StaticFiles overlay URL existence-filtering — partial overlays list only
#      the files that actually exist (Rack::Static would 404 otherwise).
#
# Overlay config is set on OT.conf['site'] per-test and RESET in teardown so
# later tests (and later files sharing the process) see the default pack only.
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
DEFAULT_PACK    = File.join(Onetime::HOME, 'public', 'branding', 'default')

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

# Same pack NAME under BOTH search roots, to prove etc/branding wins over
# public/branding. Cleaned up in teardown (nothing tracked lands here).
@pack_name = "trytest_#{Process.pid}"
@etc_pack_dir    = File.join(Onetime::HOME, 'etc', 'branding', @pack_name)
@public_pack_dir = File.join(Onetime::HOME, 'public', 'branding', @pack_name)
FileUtils.mkdir_p(@etc_pack_dir)
FileUtils.mkdir_p(@public_pack_dir)

# A pack that exists ONLY under public/branding (vendor root).
@vendor_only_name = "tryvendor_#{Process.pid}"
@vendor_only_dir  = File.join(Onetime::HOME, 'public', 'branding', @vendor_only_name)
FileUtils.mkdir_p(@vendor_only_dir)

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
# 1. Onetime.brand_pack_dir — two-root NAME resolution + security
# ============================================================================

## the two search roots are etc/branding then public/branding (first wins)
Onetime.brand_pack_roots.map { |r| r.sub(Onetime::HOME + '/', '') }
#=> ['etc/branding', 'public/branding']

## a pack present in BOTH roots resolves from etc/branding (operator wins)
Onetime.brand_pack_dir(@pack_name) == @etc_pack_dir
#=> true

## a pack present ONLY under public/branding resolves from the vendor root
Onetime.brand_pack_dir(@vendor_only_name) == @vendor_only_dir
#=> true

## the tracked default pack resolves under public/branding
Onetime.brand_pack_dir('default') == DEFAULT_PACK
#=> true

## a nonexistent pack name resolves to nil
Onetime.brand_pack_dir('definitely_not_a_pack_xyz')
#=> nil

## [security] a name containing '/' is rejected -> nil
Onetime.brand_pack_dir('foo/bar')
#=> nil

## [security] a name containing a backslash is rejected -> nil
Onetime.brand_pack_dir('foo\\bar')
#=> nil

## [security] a name containing '..' traversal is rejected -> nil
Onetime.brand_pack_dir('../evil')
#=> nil

## a blank name resolves to nil
Onetime.brand_pack_dir('   ')
#=> nil

# ============================================================================
# 2. resolve_brand_pack_dir / brand_overlay_dir — precedence + always-default
# ============================================================================

## nothing configured -> resolution lands on the DEFAULT pack (never nil)
clear_overlay
Onetime.brand_overlay_dir == DEFAULT_PACK
#=> true

## explicit brand_assets_dir WINS over a valid brand_pack
set_overlay(assets_dir: @overlay_favicon, pack: @pack_name)
Onetime.brand_overlay_dir == @overlay_favicon
#=> true

## blank/whitespace brand_assets_dir is skipped, brand_pack resolves
set_overlay(assets_dir: '   ', pack: @pack_name)
Onetime.brand_overlay_dir == @etc_pack_dir
#=> true

## a valid brand_pack NAME resolves across the roots (etc wins)
set_overlay(assets_dir: nil, pack: @pack_name)
Onetime.brand_overlay_dir == @etc_pack_dir
#=> true

## a nonexistent brand_pack falls back to the default pack (not nil, v2)
set_overlay(assets_dir: nil, pack: 'definitely_not_a_pack_xyz')
Onetime.brand_overlay_dir == DEFAULT_PACK
#=> true

## [security] a traversal brand_pack is rejected and falls back to default
set_overlay(assets_dir: nil, pack: '../evil')
Onetime.brand_overlay_dir == DEFAULT_PACK
#=> true

## an explicit brand_assets_dir that is missing falls back to the default pack
set_overlay(assets_dir: '/no/such/overlay/dir_xyz', pack: @pack_name)
Onetime.brand_overlay_dir == DEFAULT_PACK
#=> true

## resolve_brand_pack_dir is pure — it reads its args, not OT.conf
clear_overlay
Onetime.resolve_brand_pack_dir(brand_assets_dir: @overlay_favicon) == @overlay_favicon
#=> true

## resolve_brand_pack_dir with an unset name lands on the default pack
Onetime.resolve_brand_pack_dir(brand_pack: nil) == DEFAULT_PACK
#=> true

# ============================================================================
# 3. Onetime.brand_asset_path — overlay-first, collapses onto the pack path
# ============================================================================

## overlay hit returns the overlay copy of the file
set_overlay(assets_dir: @overlay_favicon, pack: nil)
Onetime.brand_asset_path('favicon.ico') == File.join(@overlay_favicon, 'favicon.ico')
#=> true

## overlay configured but file absent -> falls through to the DEFAULT pack file
set_overlay(assets_dir: @overlay_empty, pack: nil)
Onetime.brand_asset_path('favicon.ico') == File.join(DEFAULT_PACK, 'favicon.ico')
#=> true

## no overlay -> resolves to the DEFAULT pack file (v2 collapse)
clear_overlay
Onetime.brand_asset_path('site.webmanifest') == File.join(DEFAULT_PACK, 'site.webmanifest')
#=> true

# ============================================================================
# 4. GetFavicon#serve_default_favicon — overlay / neutral / redirect precedence
# ============================================================================

## overlay favicon.ico is served when present
OT.conf['brand'] = {}
set_overlay(assets_dir: @overlay_favicon, pack: nil)
logic = run_default_favicon
[logic.icon_data, logic.content_type, logic.redirect_url]
#=> ['OVERLAY-ICO-BYTES', 'image/x-icon', nil]

## overlay missing the file falls through to the neutral default-pack favicon
OT.conf['brand'] = {}
set_overlay(assets_dir: @overlay_empty, pack: nil)
logic = run_default_favicon
neutral = File.binread(File.join(DEFAULT_PACK, 'favicon.ico'))
[logic.icon_data == neutral, logic.content_type, logic.redirect_url]
#=> [true, 'image/x-icon', nil]

## BRAND_FAVICON_URL https redirect wins over the overlay (higher precedence)
OT.conf['brand'] = { 'favicon_url' => 'https://cdn.acme.test/favicon.ico' }
set_overlay(assets_dir: @overlay_favicon, pack: nil)
logic = run_default_favicon
[logic.redirect_url, logic.icon_data]
#=> ['https://cdn.acme.test/favicon.ico', nil]

# ============================================================================
# 5. GetWebmanifest#load_base_manifest — overlay / brand overlay / fallbacks
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

## overlay missing site.webmanifest falls back to the neutral default-pack manifest
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
# 6. StaticFiles overlay URL existence-filtering (partial overlay)
# ============================================================================

## partial overlay: only the file that exists is listed for the overlay layer
set_overlay(assets_dir: @overlay_partial, pack: nil)
overlay_dir = Onetime.brand_overlay_dir
BRAND_PACK_URLS.select { |u| File.exist?(File.join(overlay_dir, u)) }
#=> ['/favicon.svg']

## absent overlay files are excluded (they fall through to the default-pack base layer)
set_overlay(assets_dir: @overlay_partial, pack: nil)
overlay_dir = Onetime.brand_overlay_dir
present = BRAND_PACK_URLS.select { |u| File.exist?(File.join(overlay_dir, u)) }
absent  = (BRAND_PACK_URLS - present).sort
[present, absent]
#=> [['/favicon.svg'], ['/apple-touch-icon.png', '/icon-192.png', '/icon-512.png', '/safari-pinned-tab.svg', '/social-preview.png']]

## the default pack (base layer) carries the full BRAND_PACK_URLS set
BRAND_PACK_URLS.all? { |u| File.exist?(File.join(DEFAULT_PACK, u)) }
#=> true

# Teardown — restore the no-overlay baseline and remove fixtures.
OT.conf['brand']                    = @orig_brand
OT.conf['site']['brand_assets_dir'] = @orig_assets_dir
OT.conf['site']['brand_pack']       = @orig_pack
[@overlay_favicon, @overlay_manifest, @overlay_bad_manifest,
 @overlay_empty, @overlay_partial].each { |d| FileUtils.remove_entry(d) rescue nil }
[@etc_pack_dir, @public_pack_dir, @vendor_only_dir].each { |d| FileUtils.remove_entry(d) rescue nil }
FileUtils.remove_entry(File.join(Onetime::HOME, 'etc', 'branding')) if Dir.exist?(File.join(Onetime::HOME, 'etc', 'branding')) && Dir.empty?(File.join(Onetime::HOME, 'etc', 'branding'))

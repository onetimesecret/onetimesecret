# try/unit/web/brand_pack_diagnostics_try.rb
#
# frozen_string_literal: true

#
# Onetime.brand_pack_diagnostics — read-only brand-pack resolution introspection
# (#3822, follow-up to the v0.26.0 UK neutral-branding incident).
#
# The method is the SINGLE SOURCE OF TRUTH consumed by two thin adapters
# (`bin/ots config brand` and the Colonel `GET /system/brand` endpoint), so the
# payload shape here is a hard contract. Coverage:
#
#   1. Payload shape + string keys throughout.
#   2. Nothing configured -> lands on the default pack, NOT a fallback.
#   3. Valid non-default pack whose manifest matches conf -> no fallback, no
#      boot/live mismatch, brand_absorbed populated.
#   4. Mount-race TRUE positive: disk manifest diverges from the frozen conf with
#      NO env override -> boot_vs_live_mismatch == true.
#   5. Env-override FALSE-positive guard: same divergence, but the backing
#      BRAND_* env IS set -> boot_vs_live_mismatch == false (correctness linchpin).
#   6. Non-default pack missing on disk -> fell_back_to_default == true.
#   7. Malformed brand.yaml -> empty contribution via the rescue, not an exception.
#   8. env.brand_pack mirrors raw ENV['BRAND_PACK'] right now.
#
# All OT.conf / ENV / temp-dir state is set per-test and RESTORED in teardown so
# later files sharing the process see the default pack only.
#

require 'json'
require 'tmpdir'
require 'fileutils'
require_relative '../../support/test_helpers'

OT.boot! :test, false

require 'onetime/middleware/static_files'

DEFAULT_PACK = File.join(Onetime::HOME, 'public', 'branding', 'default')

OT.conf['site'] ||= {}

# Capture originals so teardown fully restores the no-overlay baseline.
@orig_assets_dir      = OT.conf['site']['brand_assets_dir']
@orig_pack            = OT.conf['site']['brand_pack']
@orig_brand           = OT.conf['brand']
@orig_env_pack        = ENV['BRAND_PACK']
@orig_env_assets      = ENV['BRAND_ASSETS_DIR']
@orig_env_prod_name   = ENV['BRAND_PRODUCT_NAME']

# --- Fixtures --------------------------------------------------------------

# A non-default pack carrying a real brand.yaml identity scalar. Used as an
# explicit brand_assets_dir (which WINS over brand_pack) so resolution lands
# here directly.
@pack_with_manifest = Dir.mktmpdir('ots-diag-pack')
File.write(File.join(@pack_with_manifest, 'brand.yaml'), %(product_name: "Acme Diagnostics"\n))
# Prove overlay_assets is existence-filtered live: carry one mandatory asset.
File.write(File.join(@pack_with_manifest, 'favicon.svg'), '<svg/>')

# A pack whose brand.yaml is malformed YAML (unterminated flow sequence), to
# exercise the rescue in read_brand_manifest_scalars.
@bad_manifest_pack = Dir.mktmpdir('ots-diag-badpack')
File.write(File.join(@bad_manifest_pack, 'brand.yaml'), %(product_name: [1, 2\n))

def set_overlay(assets_dir: nil, pack: nil)
  OT.conf['site']['brand_assets_dir'] = assets_dir
  OT.conf['site']['brand_pack']       = pack
end

def clear_overlay
  OT.conf['site']['brand_assets_dir'] = nil
  OT.conf['site']['brand_pack']       = nil
end

# TRYOUTS

# ============================================================================
# 1. Payload shape — the hard contract the adapters depend on
# ============================================================================

## the payload carries exactly the documented top-level key set (string keys)
clear_overlay
Onetime.brand_pack_diagnostics.keys.sort
#=> ['boot_vs_live_mismatch', 'config', 'env', 'fell_back_to_default', 'home', 'manifest', 'overlay_assets', 'resolved_dir', 'roots']

## env carries the two raw-ENV keys
clear_overlay
Onetime.brand_pack_diagnostics['env'].keys.sort
#=> ['brand_assets_dir', 'brand_pack']

## config carries brand_pack, brand_assets_dir, and brand_absorbed
clear_overlay
Onetime.brand_pack_diagnostics['config'].keys.sort
#=> ['brand_absorbed', 'brand_assets_dir', 'brand_pack']

## manifest carries path, exists, keys_on_disk
clear_overlay
Onetime.brand_pack_diagnostics['manifest'].keys.sort
#=> ['exists', 'keys_on_disk', 'path']

## home is the install dir (Onetime::HOME)
clear_overlay
Onetime.brand_pack_diagnostics['home'] == Onetime::HOME
#=> true

## roots lists each search root in precedence order, each with a live exists flag
clear_overlay
r = Onetime.brand_pack_diagnostics['roots']
[r.map { |h| h['path'].sub(Onetime::HOME + '/', '') }, r.map { |h| h.key?('exists') }]
#=> [['etc/branding', 'public/branding'], [true, true]]

# ============================================================================
# 2. Nothing configured -> lands on the default pack, NOT a fallback
# ============================================================================

## unconfigured install resolves to the default pack and does NOT read as fallback
clear_overlay
d = Onetime.brand_pack_diagnostics
[d['fell_back_to_default'], d['resolved_dir'] == DEFAULT_PACK, d['resolved_dir'].end_with?('/default')]
#=> [false, true, true]

## config.brand_absorbed lists only non-empty brand keys from the boot snapshot
OT.conf['brand'] = { 'product_name' => 'Acme', 'primary_color' => '', 'logo_url' => nil }
clear_overlay
Onetime.brand_pack_diagnostics['config']['brand_absorbed']
#=> ['product_name']

## overlay_assets reflects on-disk presence now (default pack: mandatory set, no logo)
OT.conf['brand'] = {}
clear_overlay
oa = Onetime.brand_pack_diagnostics['overlay_assets']
[oa.include?('/favicon.svg'), oa.include?('/brand-logo.svg')]
#=> [true, false]

# ============================================================================
# 3. Valid non-default pack, manifest matches conf -> healthy
# ============================================================================

## brand_assets_dir wins and resolves to the pack; manifest scalar is read live
ENV.delete('BRAND_PRODUCT_NAME')
OT.conf['brand'] = { 'product_name' => 'Acme Diagnostics' }
set_overlay(assets_dir: @pack_with_manifest, pack: nil)
d = Onetime.brand_pack_diagnostics
[d['resolved_dir'] == @pack_with_manifest, d['manifest']['exists'], d['manifest']['keys_on_disk']]
#=> [true, true, ['product_name']]

## a healthy pack does NOT read as fallback and does NOT read as a boot/live mismatch
ENV.delete('BRAND_PRODUCT_NAME')
OT.conf['brand'] = { 'product_name' => 'Acme Diagnostics' }
set_overlay(assets_dir: @pack_with_manifest, pack: nil)
d = Onetime.brand_pack_diagnostics
[d['fell_back_to_default'], d['boot_vs_live_mismatch'], d['config']['brand_absorbed'].include?('product_name')]
#=> [false, false, true]

# ============================================================================
# 4. Mount-race TRUE positive (the key deliverable)
# ============================================================================

## disk manifest diverges from frozen conf with NO env override -> boot_vs_live_mismatch
ENV.delete('BRAND_PRODUCT_NAME')
OT.conf['brand'] = { 'product_name' => 'Stale Neutral' } # what a pre-mount boot absorbed
set_overlay(assets_dir: @pack_with_manifest, pack: nil)
d = Onetime.brand_pack_diagnostics
[d['manifest']['exists'], d['manifest']['keys_on_disk'], d['boot_vs_live_mismatch']]
#=> [true, ['product_name'], true]

# ============================================================================
# 5. Env-override FALSE-positive guard (correctness linchpin)
# ============================================================================

## SAME divergence as (4) but the backing BRAND_* env IS set -> NOT a mismatch.
## Without the env-exclusion this would false-positive on every legitimate
## BRAND_* override; conf differs from disk here precisely BECAUSE env wins.
ENV['BRAND_PRODUCT_NAME'] = 'Acme From Env'
OT.conf['brand'] = { 'product_name' => 'Stale Neutral' } # still differs from disk 'Acme Diagnostics'
set_overlay(assets_dir: @pack_with_manifest, pack: nil)
Onetime.brand_pack_diagnostics['boot_vs_live_mismatch']
#=> false

## a blank/whitespace env value does NOT count as an override (guard stays armed)
ENV['BRAND_PRODUCT_NAME'] = '   '
OT.conf['brand'] = { 'product_name' => 'Stale Neutral' }
set_overlay(assets_dir: @pack_with_manifest, pack: nil)
Onetime.brand_pack_diagnostics['boot_vs_live_mismatch']
#=> true

# ============================================================================
# 6. Non-default pack configured but missing on disk -> fell_back_to_default
# ============================================================================

## a non-default pack NAME that resolves to nothing serves the default pack
ENV.delete('BRAND_PRODUCT_NAME')
OT.conf['brand'] = {}
set_overlay(assets_dir: nil, pack: 'definitely_not_a_pack_xyz')
d = Onetime.brand_pack_diagnostics
[d['fell_back_to_default'], d['resolved_dir'] == DEFAULT_PACK, d['config']['brand_pack']]
#=> [true, true, 'definitely_not_a_pack_xyz']

## explicit brand_assets_dir that is missing also falls back to the default pack
OT.conf['brand'] = {}
set_overlay(assets_dir: '/no/such/overlay/dir_xyz', pack: nil)
d = Onetime.brand_pack_diagnostics
[d['fell_back_to_default'], d['resolved_dir'] == DEFAULT_PACK]
#=> [true, true]

# ============================================================================
# 7. Malformed manifest -> empty contribution via rescue (never raises)
# ============================================================================

## a malformed brand.yaml surfaces as an empty contribution, not an exception
ENV.delete('BRAND_PRODUCT_NAME')
OT.conf['brand'] = {}
set_overlay(assets_dir: @bad_manifest_pack, pack: nil)
d = Onetime.brand_pack_diagnostics
[d['manifest']['exists'], d['manifest']['keys_on_disk'], d['boot_vs_live_mismatch']]
#=> [true, [], false]

## the internal helper returns {} for a malformed manifest path
Onetime.read_brand_manifest_scalars(File.join(@bad_manifest_pack, 'brand.yaml'))
#=> {}

## the internal helper returns {} for a nonexistent path
Onetime.read_brand_manifest_scalars('/no/such/brand.yaml')
#=> {}

# ============================================================================
# 8. env.* mirrors raw ENV right now
# ============================================================================

## env.brand_pack reflects ENV['BRAND_PACK'] as set in this process
ENV['BRAND_PACK'] = 'onetimesecret'
clear_overlay
Onetime.brand_pack_diagnostics['env']['brand_pack']
#=> 'onetimesecret'

## env.brand_pack is nil when the var is unset (env not reaching the container)
ENV.delete('BRAND_PACK')
clear_overlay
Onetime.brand_pack_diagnostics['env']['brand_pack']
#=> nil

# Teardown — restore the no-overlay baseline, ENV, and remove fixtures.
OT.conf['brand']                    = @orig_brand
OT.conf['site']['brand_assets_dir'] = @orig_assets_dir
OT.conf['site']['brand_pack']       = @orig_pack
@orig_env_pack.nil?      ? ENV.delete('BRAND_PACK')         : (ENV['BRAND_PACK'] = @orig_env_pack)
@orig_env_assets.nil?    ? ENV.delete('BRAND_ASSETS_DIR')   : (ENV['BRAND_ASSETS_DIR'] = @orig_env_assets)
@orig_env_prod_name.nil? ? ENV.delete('BRAND_PRODUCT_NAME') : (ENV['BRAND_PRODUCT_NAME'] = @orig_env_prod_name)
[@pack_with_manifest, @bad_manifest_pack].each { |d| FileUtils.remove_entry(d) rescue nil }

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
#   5b. Operator-config provenance guard: an operator-set key (recorded in
#      conf['brand_manifest']['operator_keys']) differing from a differing pack
#      manifest is NOT a race; a non-operator key still IS (stale-content kept).
#   6. Non-default pack missing on disk -> fell_back_to_default == true.
#   7. Malformed / non-mapping brand.yaml -> empty contribution via the guard/
#      rescue, not an exception.
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

# Derive the default pack dir from the resolver rather than hardcoding the path,
# so this test tracks brand_pack_dir's resolution (root precedence, existence) if
# it ever changes (#10).
DEFAULT_PACK = Onetime.brand_pack_dir(Onetime::DEFAULT_BRAND_PACK)

OT.conf['site'] ||= {}

# Capture originals so teardown fully restores the no-overlay baseline.
@orig_assets_dir      = OT.conf['site']['brand_assets_dir']
@orig_pack            = OT.conf['site']['brand_pack']
@orig_brand           = OT.conf['brand']
@orig_brand_manifest  = OT.conf['brand_manifest']
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

# A pack whose brand.yaml parses to a NON-Hash top level (a bare scalar). Valid
# YAML, but not a mapping, so it contributes nothing — exercises the
# `return {} unless manifest.is_a?(Hash)` guard in read_brand_manifest_scalars.
@nonhash_manifest_pack = Dir.mktmpdir('ots-diag-nonhashpack')
File.write(File.join(@nonhash_manifest_pack, 'brand.yaml'), %(hello\n))

# A pack whose brand.yaml EXISTS but carries no identity scalars (comment only),
# so manifest_exists stays true while live_scalars comes back empty. Used for #8
# (a key recorded in absorbed_keys but absent from disk NOW — a since-removed
# manifest key) and for the legacy-provenance guard.
@manifestless_pack = Dir.mktmpdir('ots-diag-nokeys')
File.write(File.join(@manifestless_pack, 'brand.yaml'), %(# no identity scalars\n))

# A pack that mounts an ASSET (favicon) alongside a value-free brand.yaml — the
# #7 asset-only-race shape: overlay_assets is non-empty but there are no scalars
# to diff, so the scalar detector stays silent by design.
@asset_only_pack = Dir.mktmpdir('ots-diag-assetonly')
File.write(File.join(@asset_only_pack, 'brand.yaml'), %(# assets only, no scalars\n))
File.write(File.join(@asset_only_pack, 'favicon.svg'), '<svg/>')

# A pack whose brand.yaml was WHOLLY removed (file gone) but that still resolves
# because an asset (favicon) lingers on disk. Exercises the #8 whole-file-removal
# branch: manifest_exists is FALSE and live_scalars is empty, yet absorbed_keys
# still names a value frozen in conf — so the union scan must admit on
# absorbed_keys alone (manifest_exists must not short-circuit it).
@removed_manifest_pack = Dir.mktmpdir('ots-diag-removed')
File.write(File.join(@removed_manifest_pack, 'favicon.svg'), '<svg/>')

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
# 2b. #9 explicit-default is neutral-by-choice, NOT a fallback
# ============================================================================
#
# An operator MAY deliberately pin brand_assets_dir (or brand_pack) AT the
# default pack to serve neutral branding on purpose. Resolution honors it and
# lands on the default — but that is intent satisfied, not a fallback, so it must
# NOT set fell_back_to_default (which would exit `bin/ots config brand` 1 on a
# valid config). Before #9 any non-empty brand_assets_dir tripped the gate.

## brand_assets_dir pinned at the default pack (absolute) -> resolves there, NOT a fallback
OT.conf['brand'] = {}
set_overlay(assets_dir: DEFAULT_PACK, pack: nil)
d = Onetime.brand_pack_diagnostics
[d['resolved_dir'] == DEFAULT_PACK, d['fell_back_to_default']]
#=> [true, false]

## same pin as a HOME-relative path -> normalized to the default pack, NOT a fallback
OT.conf['brand'] = {}
set_overlay(assets_dir: 'public/branding/default', pack: nil)
d = Onetime.brand_pack_diagnostics
[d['resolved_dir'] == DEFAULT_PACK, d['fell_back_to_default']]
#=> [true, false]

## brand_pack pinned at the default NAME -> resolves there, NOT a fallback (parity)
OT.conf['brand'] = {}
set_overlay(assets_dir: nil, pack: 'default')
d = Onetime.brand_pack_diagnostics
[d['resolved_dir'] == DEFAULT_PACK, d['fell_back_to_default']]
#=> [true, false]

## a TRAILING-SLASH default pin normalizes to the default pack, NOT a fallback.
## The resolver preserves the slash in resolved_dir, and assets_norm carries the
## same slash, so intent-vs-served stay in lockstep and the flag holds false. This
## pins the byte-identical invariant: a future canonicalization that strips the
## slash from resolved_dir but not assets_norm would flip this to a false positive.
OT.conf['brand'] = {}
set_overlay(assets_dir: 'public/branding/default/', pack: nil)
d = Onetime.brand_pack_diagnostics
[d['resolved_dir'].chomp('/') == DEFAULT_PACK, d['fell_back_to_default']]
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
# 5b. Operator-config provenance guard (the #1 correctness bug)
# ============================================================================
#
# Precedence is defaults < pack brand.yaml < operator brand: config < BRAND_*
# env, and apply_brand_manifest fills ONLY keys the operator left nil. So a key
# the operator SET in config legitimately differs from a pack shipping a
# DIFFERENT value for it — that is NOT a mount race. Boot records the operator's
# keys in conf['brand_manifest']['operator_keys']; the detector must skip them.

## operator-set key differing from a differing on-disk manifest (NO env) -> NOT a race.
## This is the exact false-positive the old (env-only) exclusion missed.
ENV.delete('BRAND_PRODUCT_NAME')
OT.conf['brand']          = { 'product_name' => 'Operator Chosen' } # what the operator set in config
OT.conf['brand_manifest'] = { 'operator_keys' => ['product_name'] } # provenance as boot records it
set_overlay(assets_dir: @pack_with_manifest, pack: nil) # pack ships 'Acme Diagnostics'
Onetime.brand_pack_diagnostics['boot_vs_live_mismatch']
#=> false

## a key NOT in operator_keys, boot conf differing from disk -> STILL a race (stale-content
## detection is preserved: operator provenance must not blanket-suppress real drift).
ENV.delete('BRAND_PRODUCT_NAME')
OT.conf['brand']          = { 'product_name' => 'Stale Neutral' } # filled from a stale pack at boot
OT.conf['brand_manifest'] = { 'operator_keys' => [] }             # operator set nothing
set_overlay(assets_dir: @pack_with_manifest, pack: nil)
Onetime.brand_pack_diagnostics['boot_vs_live_mismatch']
#=> true

# ============================================================================
# 5c. #8 removed-key provenance — a since-removed manifest key still detected
# ============================================================================
#
# apply_brand_manifest records the keys it absorbed FROM the pack in
# conf['brand_manifest']['absorbed_keys']. If such a key is later REMOVED from
# brand.yaml on disk, it lingers in the frozen boot conf but is absent from a
# live disk re-read (live_scalars) — a disk-only scan misses the divergence. The
# union of live_scalars with absorbed_keys catches it, provenance-gated so a
# legacy/default-filled conf key (never pack-sourced) is NOT flagged (#3612).

## an absorbed key REMOVED from disk (empty live_scalars) but lingering in conf
## with a non-empty value -> STILL a race (the disk-only scan would have missed it).
ENV.delete('BRAND_PRODUCT_NAME')
OT.conf['brand']          = { 'product_name' => 'Absorbed At Boot' } # lingering pack value
OT.conf['brand_manifest'] = { 'operator_keys' => [], 'absorbed_keys' => ['product_name'] }
set_overlay(assets_dir: @manifestless_pack, pack: nil) # brand.yaml exists, defines no product_name
d = Onetime.brand_pack_diagnostics
[d['manifest']['exists'], d['manifest']['keys_on_disk'], d['boot_vs_live_mismatch']]
#=> [true, [], true]

## converse: same removal but the lingering conf value is ALSO empty -> nothing
## diverges (empty conf == absent disk), so NOT a race. Provenance alone never flags.
ENV.delete('BRAND_PRODUCT_NAME')
OT.conf['brand']          = { 'product_name' => '' }
OT.conf['brand_manifest'] = { 'operator_keys' => [], 'absorbed_keys' => ['product_name'] }
set_overlay(assets_dir: @manifestless_pack, pack: nil)
Onetime.brand_pack_diagnostics['boot_vs_live_mismatch']
#=> false

## a legacy/default-filled key NOT in absorbed_keys that the pack does not offer is
## NOT flagged: only positive pack provenance is scanned, so back-compat paths
## (config.rb LEGACY_BRAND_FALLBACKS) never read as a race — the false-positive a
## naive union-over-conf['brand'] fix would introduce (#3612).
ENV.delete('BRAND_PRODUCT_NAME')
OT.conf['brand']          = { 'product_name' => 'Legacy SITE_NAME Value' }
OT.conf['brand_manifest'] = { 'operator_keys' => [], 'absorbed_keys' => [] }
set_overlay(assets_dir: @manifestless_pack, pack: nil)
Onetime.brand_pack_diagnostics['boot_vs_live_mismatch']
#=> false

## the WHOLE brand.yaml removed since boot (file gone, pack still resolves via a
## lingering favicon): manifest_exists is FALSE, yet an absorbed key still lingers
## in conf -> STILL a race. The union must admit on absorbed_keys alone here, since
## manifest_exists is false and would otherwise short-circuit the scan (#8).
ENV.delete('BRAND_PRODUCT_NAME')
OT.conf['brand']          = { 'product_name' => 'Absorbed At Boot' }
OT.conf['brand_manifest'] = { 'operator_keys' => [], 'absorbed_keys' => ['product_name'] }
set_overlay(assets_dir: @removed_manifest_pack, pack: nil) # NO brand.yaml on disk
d = Onetime.brand_pack_diagnostics
[d['manifest']['exists'], d['boot_vs_live_mismatch']]
#=> [false, true]

## converse of the whole-file removal: NO absorbed_keys either (asset-only shape,
## brand.yaml gone) -> the union is empty, .any? is false, so this correctly does
## NOT flag. This is what keeps the manifest_exists||absorbed_keys.any? guard from
## regressing the #7 asset-only-reads-healthy contract.
ENV.delete('BRAND_PRODUCT_NAME')
OT.conf['brand']          = {}
OT.conf['brand_manifest'] = { 'operator_keys' => [], 'absorbed_keys' => [] }
set_overlay(assets_dir: @removed_manifest_pack, pack: nil)
Onetime.brand_pack_diagnostics['boot_vs_live_mismatch']
#=> false

# ============================================================================
# 5d. #7 asset-only race — documented deferral (pins current behavior)
# ============================================================================
#
# A non-default pack that mounts its ASSETS but ships no identity scalars is an
# asset-only race. The scalar detector intentionally does NOT auto-flag it:
# boot_vs_live_mismatch stays false (no scalars to diff) and fell_back_to_default
# stays false (a non-default pack DID resolve), so `bin/ots config brand` exits 0.
# overlay_assets still surfaces the asset for manual cross-region diffing. An
# automatic signal awaits StaticFiles boot-baseline instrumentation. Pinned here
# so any future change to this behavior is deliberate, not accidental.

## asset-only race reads healthy on both danger flags; overlay_assets carries the asset
ENV.delete('BRAND_PRODUCT_NAME')
OT.conf['brand']          = {}
OT.conf['brand_manifest'] = { 'operator_keys' => [], 'absorbed_keys' => [] }
set_overlay(assets_dir: @asset_only_pack, pack: nil)
d = Onetime.brand_pack_diagnostics
[d['boot_vs_live_mismatch'], d['fell_back_to_default'], d['overlay_assets'].include?('/favicon.svg')]
#=> [false, false, true]

# Reset provenance so later sections see the no-operator-keys baseline.
OT.conf['brand_manifest'] = { 'operator_keys' => [], 'absorbed_keys' => [] }

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

## a brand.yaml parsing to a NON-Hash top level (bare scalar) contributes nothing
ENV.delete('BRAND_PRODUCT_NAME')
OT.conf['brand'] = {}
set_overlay(assets_dir: @nonhash_manifest_pack, pack: nil)
d = Onetime.brand_pack_diagnostics
[d['manifest']['exists'], d['manifest']['keys_on_disk'], d['boot_vs_live_mismatch']]
#=> [true, [], false]

## the internal helper returns {} for a malformed manifest path
Onetime.read_brand_manifest_scalars(File.join(@bad_manifest_pack, 'brand.yaml'))
#=> {}

## the internal helper returns {} for a manifest whose top level is not a mapping
Onetime.read_brand_manifest_scalars(File.join(@nonhash_manifest_pack, 'brand.yaml'))
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

# Teardown — restore the no-overlay baseline, ENV, and remove fixtures. The
# OT.conf restore is wrapped so the PROCESS-GLOBAL cleanup (ENV vars + temp dirs)
# still runs even if a conf restore raises: that state, not OT.conf, is what
# poisons sibling try files sharing this process (#11).
begin
  OT.conf['brand']                    = @orig_brand
  OT.conf['brand_manifest']           = @orig_brand_manifest
  OT.conf['site']['brand_assets_dir'] = @orig_assets_dir
  OT.conf['site']['brand_pack']       = @orig_pack
ensure
  @orig_env_pack.nil?      ? ENV.delete('BRAND_PACK')         : (ENV['BRAND_PACK'] = @orig_env_pack)
  @orig_env_assets.nil?    ? ENV.delete('BRAND_ASSETS_DIR')   : (ENV['BRAND_ASSETS_DIR'] = @orig_env_assets)
  @orig_env_prod_name.nil? ? ENV.delete('BRAND_PRODUCT_NAME') : (ENV['BRAND_PRODUCT_NAME'] = @orig_env_prod_name)
  [@pack_with_manifest, @bad_manifest_pack, @nonhash_manifest_pack,
   @manifestless_pack, @asset_only_pack, @removed_manifest_pack].each { |d| FileUtils.remove_entry(d) rescue nil }
end

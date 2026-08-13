# try/unit/web/brand_pack_default_try.rb
#
# frozen_string_literal: true

#
# Tracked default brand pack — contract + drift guards (v2, #3774)
#
# public/branding/default is the ONE tracked pack: every unset BRAND_PACK
# resolves to it, so it must (a) carry the full canonical asset set, (b) stay
# value-free so an unconfigured install keeps brand.* nil (#3049), and (c) keep
# its manifest whitelist in lockstep with Config::BRAND_ENV.
#
# These are static-file / constant assertions — no Redis, no full boot needed
# beyond loading the config constants.
#

require 'yaml'
require 'set'
require_relative '../../support/test_helpers'

OT.boot! :test, false

DEFAULT_PACK  = File.join(Onetime::HOME, 'public', 'branding', 'default')
BRAND_YAML    = File.join(DEFAULT_PACK, 'brand.yaml')

# The served, root-mounted assets a complete pack carries (favicon.ico and
# site.webmanifest are served by routes; the rest by StaticFiles).
CANONICAL_ASSETS = %w[
  favicon.ico favicon.svg apple-touch-icon.png icon-192.png icon-512.png
  safari-pinned-tab.svg site.webmanifest
].freeze

# Assets a pack MAY carry. Optional because they are opt-in by nature, not
# because they are unimportant:
#   - brand-logo.*    — a pack-carried masthead logo (#3774), inert until
#                       brand.logo_url points at it.
#   - social-preview.png — the og:image/twitter:image card (#4150). The default
#                       and example packs DO ship one; a pack may omit it, and
#                       then no image meta tags are emitted at all (not a broken
#                       tag pointing at a 404). Serving and linking both key off
#                       this file's existence — see StaticFiles, head.rue and
#                       Config#normalize_brand.
OPTIONAL_ASSETS = %w[
  social-preview.png brand-logo.svg brand-logo.png
  brand-logo-dark.svg brand-logo-dark.png
].freeze

# TRYOUTS

# ============================================================================
# 1. Canonical file set
# ============================================================================

## the default pack carries every canonical served asset
CANONICAL_ASSETS.all? { |f| File.file?(File.join(DEFAULT_PACK, f)) }
#=> true

## the default pack contains ONLY canonical + optional assets + brand.yaml (no cruft)
entries = Dir.children(DEFAULT_PACK).reject { |e| e.start_with?('.') }.sort
(entries - (CANONICAL_ASSETS + OPTIONAL_ASSETS + ['brand.yaml'])).empty?
#=> true

## the default pack carries every canonical asset with nothing canonical missing
entries = Dir.children(DEFAULT_PACK).reject { |e| e.start_with?('.') }.sort
(CANONICAL_ASSETS - entries).empty?
#=> true

## the tracked default pack ships a social card (neutral, like the rest of the pack)
File.file?(File.join(DEFAULT_PACK, 'social-preview.png'))
#=> true

## the manifest file exists
File.file?(BRAND_YAML)
#=> true

# ============================================================================
# 2. The default manifest is value-free (neutral posture, #3049 / #3774)
# ============================================================================

## YAML.safe_load(default brand.yaml) is nil/empty — no brand values ship here
loaded = YAML.safe_load(File.read(BRAND_YAML, encoding: 'UTF-8'))
loaded.nil? || (loaded.respond_to?(:empty?) && loaded.empty?)
#=> true

## every identity line in the template is COMMENTED (no uncommented key: value)
File.read(BRAND_YAML, encoding: 'UTF-8').lines.any? { |l| l.match?(/\A[a-z_]+:/) }
#=> false

# ============================================================================
# 3. Manifest whitelist drift guard: commented keys == BRAND_MANIFEST_KEYS == BRAND_ENV
# ============================================================================

## the manifest whitelist is exactly the BRAND_ENV key set
Onetime::Config::BRAND_MANIFEST_KEYS.sort == Onetime::Config::BRAND_ENV.keys.sort
#=> true

## the keys documented (commented) in the default brand.yaml == the whitelist
documented = File.read(BRAND_YAML, encoding: 'UTF-8').lines.filter_map { |l| l[/\A#\s+([a-z_]+):/, 1] }
documented.sort == Onetime::Config::BRAND_MANIFEST_KEYS.sort
#=> true

## button_text_light is intentionally NOT manifest-settable (env/YAML-only)
Onetime::Config::BRAND_MANIFEST_KEYS.include?('button_text_light')
#=> false

# ============================================================================
# 4. Social card is resolved FROM THE PACK ASSET, not a hardcoded path (#4150)
#
#    normalize_brand is the single place the default is decided, so the served
#    URL (StaticFiles existence filter) and the emitted tag (head.rue) can never
#    disagree: both key off the same file being present in the resolved pack.
# ============================================================================

## a pack CARRYING social-preview.png resolves the card to the pack file
conf = YAML.load(YAML.dump(OT.conf))
conf['site']['brand_pack'] = 'vshare' # tracked sample pack; ships a card
conf['brand']              = {}
Onetime::Config.send(:normalize_brand, conf)
conf.dig('brand', 'og_image_url')
#=> '/social-preview.png'

## the default pack carries one too, so an unconfigured install still gets a card
conf = YAML.load(YAML.dump(OT.conf))
conf['site']['brand_pack'] = 'default'
conf['brand']              = {}
Onetime::Config.send(:normalize_brand, conf)
conf.dig('brand', 'og_image_url')
#=> '/social-preview.png'

## `none` is the explicit opt-out — the one an install whose pack DOES carry a
## card (or that falls through to the default pack's card) has to use
conf = YAML.load(YAML.dump(OT.conf))
conf['site']['brand_pack'] = 'default'
conf['brand']              = { 'og_image_url' => 'none' }
Onetime::Config.send(:normalize_brand, conf)
conf.dig('brand', 'og_image_url')
#=> nil

## the opt-out sentinel is case/whitespace tolerant (env vars arrive messy)
conf = YAML.load(YAML.dump(OT.conf))
conf['brand'] = { 'og_image_url' => '  NONE ' }
Onetime::Config.send(:normalize_brand, conf)
conf.dig('brand', 'og_image_url')
#=> nil

## the existence gate is a real file check, not an assumption about pack contents
conf = YAML.load(YAML.dump(OT.conf))
Onetime::Config.send(:brand_pack_carries?, conf, 'no-such-asset.png')
#=> false

## an explicit og_image_url always wins over pack resolution
conf = YAML.load(YAML.dump(OT.conf))
conf['site']['brand_pack'] = 'vshare'
conf['brand']              = { 'og_image_url' => 'https://cdn.acme.test/card.png' }
Onetime::Config.send(:normalize_brand, conf)
conf.dig('brand', 'og_image_url')
#=> 'https://cdn.acme.test/card.png'

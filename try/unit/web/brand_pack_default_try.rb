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
  safari-pinned-tab.svg social-preview.png site.webmanifest
].freeze

# TRYOUTS

# ============================================================================
# 1. Canonical file set
# ============================================================================

## the default pack carries every canonical served asset
CANONICAL_ASSETS.all? { |f| File.file?(File.join(DEFAULT_PACK, f)) }
#=> true

## the default pack contains EXACTLY the canonical assets + brand.yaml (no cruft)
entries = Dir.children(DEFAULT_PACK).reject { |e| e.start_with?('.') }.sort
entries == (CANONICAL_ASSETS + ['brand.yaml']).sort
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

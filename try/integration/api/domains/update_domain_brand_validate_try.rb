# try/integration/api/domains/update_domain_brand_validate_try.rb
#
# frozen_string_literal: true

#
# Integration tests for BrandSettings.validate!() through UpdateDomainBrand
# logic class (issue #3048, PR #3054 review).
#
# Why this file exists:
#   PR review flagged that BrandSettings.validate!() is only covered at the
#   unit level. validate!() runs on writes (strict), while from_hash() runs
#   on reads (tolerant). This file exercises validate!() through the actual
#   API entry point — DomainsAPI::Logic::Domains::UpdateDomainBrand — to
#   guard the strict-write path end-to-end.
#
# Validation layering inside UpdateDomainBrand#validate_brand_values:
#   1. sanitize_text_fields    (truncates, never rejects)
#   2. validate_color          (per-field: format only — does NOT check WCAG)
#   3. validate_extra_colors   (per-field: secondary/background/text format)
#   4. validate_font           (per-field)
#   5. validate_heading_font   (per-field)
#   6. validate_corner_style   (per-field)
#   7. validate_border_radius  (per-field: preset or 0-64 px)
#   8. validate_default_ttl    (per-field)
#   9. validate_urls           (per-field: same valid_url? as model)
#  10. BrandSettings.validate! (model-level catch-all — owns WCAG contrast)
#
# Coverage focus:
#   - WCAG contrast rejection is the discriminator: it is ONLY enforced by
#     BrandSettings.validate!(), so a contrast-failing color pair proves
#     the model-level call site is reached.
#   - Invalid URL is caught by the per-field validator BEFORE validate!()
#     runs, but still produces the expected end-to-end form error — so we
#     test it as a path-level regression guard, not as a "reaches validate!"
#     assertion.
#   - A happy-path call asserts the model-level call site actually fires
#     (spy on BrandSettings.validate!) so a future refactor that drops the
#     defense-in-depth call would be caught.

require_relative '../../../support/test_helpers'
require_relative '../../../support/test_logic'

OT.boot! :test

# Load DomainsAPI logic classes
require 'apps/api/domains/logic/base'
require 'apps/api/domains/logic/domains/update_domain_brand'

# Setup test fixtures with unique identifiers
@ts        = Familia.now.to_i
@entropy   = SecureRandom.hex(4)
@owner     = Onetime::Customer.create!(email: "brand_validate_#{@ts}_#{@entropy}@test.com")
@org       = Onetime::Organization.create!("Brand Validate Corp #{@ts}", @owner, "brand_org_#{@ts}@test.com")

# Disable billing so the org is granted custom_branding via STANDALONE_ENTITLEMENTS
@org.define_singleton_method(:billing_enabled?) { false }

# Create a domain owned by the org
@domain = Onetime::CustomDomain.create!("brand-#{@ts}.example.com", @org.objid)
@extid  = @domain.extid

# Authenticated strategy result with org context
@session         = {}
@strategy_result = MockStrategyResult.new(
  session: @session,
  user: @owner,
  metadata: { organization_context: { organization: @org } },
)

# Helper to build a fresh logic instance per test (process_params runs in init)
def build_logic(extid:, brand:, strategy_result:)
  params = { 'extid' => extid, 'brand' => brand }
  DomainsAPI::Logic::Domains::UpdateDomainBrand.new(strategy_result, params)
end

# Spy installer for BrandSettings.validate! — wraps the real implementation
# so we can assert the call site is reached without changing behavior.
# Returns [calls_array, uninstaller_proc].
#
# The captured `original` Method object stays bound to the prior
# implementation even after we redefine validate!, so calling it inside
# the override invokes the real validator.
def install_validate_spy
  bs_class = Onetime::CustomDomain::BrandSettings
  calls    = []
  original = bs_class.method(:validate!)
  bs_class.define_singleton_method(:validate!) do |hash|
    calls << hash
    original.call(hash)
  end
  uninstaller = lambda do
    bs_class.singleton_class.send(:remove_method, :validate!)
    bs_class.define_singleton_method(:validate!, &original)
  end
  [calls, uninstaller]
end

## Setup verification — domain exists and is owned by the org
[@domain.exists?, @domain.owner?(@owner)]
#=> [true, true]

## TEST 1: Happy path — valid payload reaches BrandSettings.validate!() and is accepted
# Spy on validate! to confirm the model-level call site fires (regression guard
# against a refactor that drops the defense-in-depth call).
@validate_calls, @uninstall_spy = install_validate_spy
@logic_ok = build_logic(
  extid: @extid,
  brand: { 'primary_color' => '#1f3a8a', 'font_family' => 'serif' },
  strategy_result: @strategy_result,
)
@logic_ok.raise_concerns
[@validate_calls.size, @validate_calls.first&.dig('primary_color')]
#=> [1, '#1F3A8A']

## TEST 1b: Spy still installed — second call appends another entry
@logic_ok2 = build_logic(
  extid: @extid,
  brand: { 'corner_style' => 'pill' },
  strategy_result: @strategy_result,
)
@logic_ok2.raise_concerns
@validate_calls.size
#=> 2

## TEST 2: WCAG contrast rejection — pure validate!() path
# #FFFF00 (yellow) on white fails the 3:1 minimum. validate_color (per-field)
# accepts it as a valid hex format, so rejection MUST come from validate!().
@logic_low_contrast = build_logic(
  extid: @extid,
  brand: { 'primary_color' => '#FFFF00' },
  strategy_result: @strategy_result,
)
@msg_contrast =
  begin
    @logic_low_contrast.raise_concerns
    nil
  rescue Onetime::FormError => ex
    ex.message
  end
@msg_contrast&.include?('fails WCAG AA accessibility')
#=> true

## TEST 3: WCAG message includes the offending color and contrast ratio
# Message now prefixes the field label (#3646: multiple validated colors), e.g.
# "Primary color #FFFF00 fails WCAG AA accessibility - contrast 1.07:1 with white".
@msg_contrast.match?(/[Pp]rimary color #FFFF00.*contrast \d+\.\d+:1 with white/) == true
#=> true

## TEST 4: Invalid URL format (http://) — caught by per-field validate_urls
@logic_bad_url = build_logic(
  extid: @extid,
  brand: { 'logo_url' => 'http://example.com/logo.png' },
  strategy_result: @strategy_result,
)
begin
  @logic_bad_url.raise_concerns
  'unexpected_success'
rescue Onetime::FormError => ex
  ex.message
end
#=> "Invalid logo url - must be https:// URL or relative path starting with /"

## TEST 5: Oversize URL (>2048 chars) — rejected by valid_url? length cap
@long_url = "https://example.com/#{'a' * 2050}"
@logic_long_url = build_logic(
  extid: @extid,
  brand: { 'logo_url' => @long_url },
  strategy_result: @strategy_result,
)
begin
  @logic_long_url.raise_concerns
  'unexpected_success'
rescue Onetime::FormError => ex
  ex.message
end
#=> "Invalid logo url - must be https:// URL or relative path starting with /"

## TEST 6: Protocol-relative URL (//evil.test) is rejected
@logic_proto_rel = build_logic(
  extid: @extid,
  brand: { 'favicon_url' => '//evil.test/icon.ico' },
  strategy_result: @strategy_result,
)
@msg_proto =
  begin
    @logic_proto_rel.raise_concerns
    nil
  rescue Onetime::FormError => ex
    ex.message
  end
@msg_proto&.include?('Invalid favicon url')
#=> true

## TEST 7: Invalid font_family — caught by per-field validator with explicit list
@logic_bad_font = build_logic(
  extid: @extid,
  brand: { 'font_family' => 'comic-sans' },
  strategy_result: @strategy_result,
)
@msg_font =
  begin
    @logic_bad_font.raise_concerns
    nil
  rescue Onetime::FormError => ex
    ex.message
  end
@msg_font
#=> 'Invalid font family - must be one of: sans, serif, mono, system, slab, rounded, humanist, geometric'

## TEST 8: Invalid corner_style — caught by per-field validator
@logic_bad_corner = build_logic(
  extid: @extid,
  brand: { 'corner_style' => 'sharp' },
  strategy_result: @strategy_result,
)
@msg_corner =
  begin
    @logic_bad_corner.raise_concerns
    nil
  rescue Onetime::FormError => ex
    ex.message
  end
@msg_corner
#=> 'Invalid corner style - must be one of: rounded, square, pill'

## TEST 9: Negative default_ttl — per-field validator rejects
@logic_bad_ttl = build_logic(
  extid: @extid,
  brand: { 'default_ttl' => -100 },
  strategy_result: @strategy_result,
)
@msg_ttl =
  begin
    @logic_bad_ttl.raise_concerns
    nil
  rescue Onetime::FormError => ex
    ex.message
  end
@msg_ttl&.include?('Invalid default TTL')
#=> true

## TEST 10: Non-integer string default_ttl — per-field validator rejects
@logic_bad_ttl_str = build_logic(
  extid: @extid,
  brand: { 'default_ttl' => 'forever' },
  strategy_result: @strategy_result,
)
@msg_ttl_str =
  begin
    @logic_bad_ttl_str.raise_concerns
    nil
  rescue Onetime::FormError => ex
    ex.message
  end
@msg_ttl_str&.include?('Invalid default TTL')
#=> true

## TEST 11: validate!() empty-hash short-circuit — empty brand payload doesn't raise
@logic_empty = build_logic(
  extid: @extid,
  brand: {},
  strategy_result: @strategy_result,
)
@logic_empty.raise_concerns
@logic_empty.instance_variable_get(:@brand_settings)
#=> {}

## TEST 12: 3-digit hex color is normalized to 6-digit before storage
@logic_short_hex = build_logic(
  extid: @extid,
  brand: { 'primary_color' => '#13F' },  # 7.14:1 contrast against white
  strategy_result: @strategy_result,
)
@logic_short_hex.raise_concerns
@logic_short_hex.instance_variable_get(:@brand_settings)['primary_color']
#=> '#1133FF'

# ============================================================================
# Text-field truncation through the logic class (gap 1 — issue #3048)
# ============================================================================
#
# sanitize_text_fields applies sanitize_plain_text(value, max_length: 500) to
# product_name, footer_text, instructions_*, description. The 500-char cap
# protects email-template alt text and page-title rendering from runaway
# pasted content. These tests confirm the truncation pathway end-to-end:
# input → process_params → raise_concerns → sanitize_text_fields → @brand_settings.
#
# raise_concerns runs the per-field validators (which don't validate text
# fields) AND the model-level validate!() which also doesn't validate text
# length, so we expect the call to succeed silently and observe the
# truncated value on @brand_settings.

## TEST 13: product_name >500 chars truncates to exactly 500
@logic_long_name = build_logic(
  extid: @extid,
  brand: { 'product_name' => 'A' * 600 },
  strategy_result: @strategy_result,
)
@logic_long_name.raise_concerns
@logic_long_name.instance_variable_get(:@brand_settings)['product_name'].length
#=> 500

## TEST 13b: truncated product_name is the leading 500 chars (slice from start)
@logic_long_name.instance_variable_get(:@brand_settings)['product_name']
#=> 'A' * 500

## TEST 14: description >500 chars truncates to exactly 500
@logic_long_desc = build_logic(
  extid: @extid,
  brand: { 'description' => 'D' * 600 },
  strategy_result: @strategy_result,
)
@logic_long_desc.raise_concerns
@logic_long_desc.instance_variable_get(:@brand_settings)['description'].length
#=> 500

## TEST 15: footer_text >500 chars truncates to exactly 500
@logic_long_footer = build_logic(
  extid: @extid,
  brand: { 'footer_text' => 'F' * 600 },
  strategy_result: @strategy_result,
)
@logic_long_footer.raise_concerns
@logic_long_footer.instance_variable_get(:@brand_settings)['footer_text'].length
#=> 500

## TEST 16: under-cap text passes through untouched (no padding/no error)
@logic_short = build_logic(
  extid: @extid,
  brand: { 'product_name' => 'Acme' },
  strategy_result: @strategy_result,
)
@logic_short.raise_concerns
@logic_short.instance_variable_get(:@brand_settings)['product_name']
#=> 'Acme'

## TEST 17: HTML tags stripped before length check (sanitize then truncate)
# Input: '<b>X</b>' * 100 = 800 chars; after tag strip 100 chars of 'X' (well under cap)
@logic_html = build_logic(
  extid: @extid,
  brand: { 'product_name' => '<b>X</b>' * 100 },
  strategy_result: @strategy_result,
)
@logic_html.raise_concerns
@logic_html.instance_variable_get(:@brand_settings)['product_name']
#=> 'X' * 100

# Teardown — uninstall spy and clean up fixtures
@uninstall_spy.call if @uninstall_spy
@domain.destroy! if @domain
@org.destroy! if @org
@owner.destroy! if @owner

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
#  10. BrandSettings.validate! (model-level format catch-all, defense-in-depth)
#
# NOTE (product decision 2026-07): WCAG contrast is no longer enforced on save.
# It was previously the ONE rejection unique to validate!() and thus served as
# "the discriminator" proving the model-level call site ran. With it gone,
# every format check in validate!() is shadowed by an identical per-field
# validator that raises FIRST (steps 2-9), so no rejection path is unique to
# validate!() anymore. The TEST 1 spy is now the sole proof that validate!()
# actually fires.
#
# Coverage focus:
#   - The happy-path spy (TEST 1) is the proof the model-level call site fires;
#     a future refactor that drops the defense-in-depth call would be caught.
#   - Malformed primary_color (TEST 2/3) is rejected end-to-end. It is caught
#     by the per-field validate_color BEFORE validate!() runs (validate!
#     enforces the same hex format as defense-in-depth), so this is a
#     path-level regression guard, not a "reaches validate!" assertion.
#   - Invalid URL is likewise caught by the per-field validator BEFORE
#     validate!() runs, but still produces the expected end-to-end form error —
#     tested as a path-level regression guard.

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

## TEST 2: Malformed primary_color — format rejection end-to-end
# WCAG contrast is no longer a rejection path (product decision 2026-07), so the
# discriminator is now a malformed hex. '#GGGGGG' is caught by the per-field
# validate_color (validate! enforces the same format as defense-in-depth); the
# TEST 1 spy — not this rejection — is what proves validate! itself runs.
@logic_bad_hex = build_logic(
  extid: @extid,
  brand: { 'primary_color' => '#GGGGGG' },
  strategy_result: @strategy_result,
)
@msg_bad_hex =
  begin
    @logic_bad_hex.raise_concerns
    nil
  rescue Onetime::FormError => ex
    ex.message
  end
@msg_bad_hex
#=> 'Invalid primary color format - must be hex code (e.g. #FF0000)'

## TEST 3: Malformed primary_color message names the format problem
@msg_bad_hex&.include?('Invalid primary color format')
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

# ============================================================================
# Extended brand-settings fields (C3 — advanced branding): heading_font,
# border_radius, expanded colors. Backend validators already exist on this
# branch; these cases exercise them end-to-end through UpdateDomainBrand and,
# for the round-trips, back out through the GET safe_dump channel.
#
# Key-type reminder:
#   - @brand_settings uses STRING keys (process_params transform_keys(&:to_s)).
#   - safe_dump[:brand] / process[:record] uses SYMBOL keys (Data#to_h) and
#     contains every member (most nil).
# Normalization reminders:
#   - validate_border_radius stores radius.to_s.strip.downcase → always String.
#   - validate_heading_font / validate_corner_style do NOT mutate their value,
#     so lowercase inputs persist verbatim.
#   - colors are normalized to 6-digit UPPERCASE at write time.
# ============================================================================

## TEST 18: heading_font enum accept — a valid expanded-allowlist value ('slab')
## passes and is stored verbatim (validate_heading_font does not mutate it)
@logic_heading_ok = build_logic(
  extid: @extid,
  brand: { 'heading_font' => 'slab' },
  strategy_result: @strategy_result,
)
@logic_heading_ok.raise_concerns
@logic_heading_ok.instance_variable_get(:@brand_settings)['heading_font']
#=> 'slab'

## TEST 19: heading_font enum reject — invalid value raises FormError naming the
## heading-font problem (message copied from validate_heading_font, update_domain_brand.rb:206)
@logic_heading_bad = build_logic(
  extid: @extid,
  brand: { 'heading_font' => 'comic-sans' },
  strategy_result: @strategy_result,
)
begin
  @logic_heading_bad.raise_concerns
  nil
rescue Onetime::FormError => ex
  ex.message
end
#=> 'Invalid heading font - must be one of: sans, serif, mono, system, slab, rounded, humanist, geometric'

## TEST 20: border_radius named presets (RADII) are accepted and normalized to lowercase
%w[none sm md lg xl].map do |preset|
  logic = build_logic(extid: @extid, brand: { 'border_radius' => preset }, strategy_result: @strategy_result)
  logic.raise_concerns
  logic.instance_variable_get(:@brand_settings)['border_radius']
end
#=> ['none', 'sm', 'md', 'lg', 'xl']

## TEST 21: border_radius 0 (min) accepted; both String and Integer inputs
## normalize to the String '0' (radius.to_s.strip.downcase)
@radius_zero_str = build_logic(extid: @extid, brand: { 'border_radius' => '0' }, strategy_result: @strategy_result)
@radius_zero_str.raise_concerns
@radius_zero_int = build_logic(extid: @extid, brand: { 'border_radius' => 0 }, strategy_result: @strategy_result)
@radius_zero_int.raise_concerns
[
  @radius_zero_str.instance_variable_get(:@brand_settings)['border_radius'],
  @radius_zero_int.instance_variable_get(:@brand_settings)['border_radius'],
]
#=> ['0', '0']

## TEST 22: border_radius 64 (RADIUS_MAX / BORDER_RADIUS_MAX_PX) accepted; normalized to '64'
@radius_max = build_logic(extid: @extid, brand: { 'border_radius' => 64 }, strategy_result: @strategy_result)
@radius_max.raise_concerns
@radius_max.instance_variable_get(:@brand_settings)['border_radius']
#=> '64'

## TEST 23: border_radius 65 (> RADIUS_MAX) rejected end-to-end
## (message copied from validate_border_radius, update_domain_brand.rb:225-229)
@radius_over = build_logic(extid: @extid, brand: { 'border_radius' => 65 }, strategy_result: @strategy_result)
begin
  @radius_over.raise_concerns
  nil
rescue Onetime::FormError => ex
  ex.message
end
#=> 'Invalid border radius - must be a preset (none, sm, md, lg, xl) or a whole number of pixels 0-64'

## TEST 24: negative border_radius rejected — '-1' fails the \A\d+\z digit check in valid_border_radius?
@radius_neg = build_logic(extid: @extid, brand: { 'border_radius' => -1 }, strategy_result: @strategy_result)
begin
  @radius_neg.raise_concerns
  nil
rescue Onetime::FormError => ex
  ex.message
end
#=> 'Invalid border radius - must be a preset (none, sm, md, lg, xl) or a whole number of pixels 0-64'

## TEST 25: GET/read round-trip — extended fields persist and read back through the
## same channel GetDomainBrand uses (safe_dump.fetch(:brand, {})). process[:record]
## is that hash; success_data nils the memoized brand_settings first, so it is a real
## Redis re-read. Colors come back normalized to 6-digit UPPERCASE. (symbol keys)
@logic_roundtrip = build_logic(
  extid: @extid,
  brand: {
    'secondary_color'  => '#a1b2c3',
    'background_color' => '#000',
    'text_color'       => '#FFFFFF',
    'heading_font'     => 'serif',
    'border_radius'    => '22',
  },
  strategy_result: @strategy_result,
)
@logic_roundtrip.raise_concerns
@record = @logic_roundtrip.process[:record]
[
  @record[:secondary_color],
  @record[:background_color],
  @record[:text_color],
  @record[:heading_font],
  @record[:border_radius],
]
#=> ['#A1B2C3', '#000000', '#FFFFFF', 'serif', '22']

## TEST 26: unknown brand key is dropped by the members-slice allowlist in
## process_params; a valid key sent alongside it survives (the slice is selective,
## not blanket). Asserted on @brand_settings — the layer where the drop happens.
@logic_unknown = build_logic(
  extid: @extid,
  brand: { 'primary_color' => '#123456', 'made_up_field' => 'x' },
  strategy_result: @strategy_result,
)
@logic_unknown.raise_concerns
@bs_unknown = @logic_unknown.instance_variable_get(:@brand_settings)
[@bs_unknown.key?('made_up_field'), @bs_unknown['primary_color']]
#=> [false, '#123456']

## TEST 27: corner_style and border_radius coexist — both persist and read back.
# Pins Q4: saving border_radius does NOT clear legacy corner_style (current behavior).
@logic_coexist = build_logic(
  extid: @extid,
  brand: { 'corner_style' => 'pill', 'border_radius' => '12' },
  strategy_result: @strategy_result,
)
@logic_coexist.raise_concerns
@coexist_record = @logic_coexist.process[:record]
[@coexist_record[:corner_style], @coexist_record[:border_radius]]
#=> ['pill', '12']

## TEST 28: border_radius 'full' (pill, 9999px) rejected — removed from RADII
## because it renders as a giant oval that clips the secret on large boxes.
@radius_full = build_logic(extid: @extid, brand: { 'border_radius' => 'full' }, strategy_result: @strategy_result)
begin
  @radius_full.raise_concerns
  nil
rescue Onetime::FormError => ex
  ex.message
end
#=> 'Invalid border radius - must be a preset (none, sm, md, lg, xl) or a whole number of pixels 0-64'

# Teardown — uninstall spy and clean up fixtures
@uninstall_spy.call if @uninstall_spy
@domain.destroy! if @domain
@org.destroy! if @org
@owner.destroy! if @owner

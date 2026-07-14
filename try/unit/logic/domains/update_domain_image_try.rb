# try/unit/logic/domains/update_domain_image_try.rb
#
# frozen_string_literal: true

# Field-specific overrides on UpdateDomainImage for the manual favicon upload
# (#3780). The base class gained overridable class methods (accepted_mime_types
# / max_image_bytes) so the icon field can widen the allowlist to .ico and drop
# the size ceiling far below the shared 2 MB image limit, WITHOUT touching the
# logo field. Also guards the FastImage nil/zero-height division and the
# pre-existing favicon_source stamping.
#
# Covers:
#   1. UpdateDomainIcon.accepted_mime_types includes image/x-icon +
#      image/vnd.microsoft.icon; UpdateDomainLogo's does NOT (still png/etc).
#   2. UpdateDomainIcon.max_image_bytes == 512KB; UpdateDomainLogo == 2MB.
#   3. An ICO upload passes raise_concerns for the icon field, and is rejected
#      for the logo field with "Invalid file type".
#   4. The divergent size ceilings are enforced behaviorally: a 600KB upload is
#      rejected for the icon ("too large") but accepted for the logo.
#   5. FastImage guard: an unmeasurable (size -> nil) or zero-height image
#      stores nil dimensions instead of raising on the ratio division.
#   6. Regression: an icon upload still stamps favicon_source='user_upload' and
#      drops the stale encoded_favicon derived cache (#3780).
#
# Hermetic: uses in-memory StringIO uploads and stubs FastImage.size, so no real
# image parsing / DNS / HTTP runs. Mirrors refresh_domain_favicon_try.rb's
# entitled-owner fixtures (billing disabled -> standalone custom_branding).
#
# Run:
#   bundle exec try --agent try/unit/logic/domains/update_domain_image_try.rb

require_relative '../../../support/test_helpers'
require_relative '../../../support/test_logic'
require 'securerandom'
require 'stringio'
require 'fastimage'

OT.boot! :test

require 'api/domains/logic/base'
require 'api/domains/logic/domains/update_domain_image'

Familia.dbclient.flushdb
OT.info 'Cleaned Redis for UpdateDomainImage test run'

@ts      = Familia.now.to_i
@entropy = SecureRandom.hex(4)

Icon = DomainsAPI::Logic::Domains::UpdateDomainIcon
Logo = DomainsAPI::Logic::Domains::UpdateDomainLogo

# --- Entitled owner fixtures (billing disabled -> standalone custom_branding) ---
@owner  = Onetime::Customer.create!(email: "img_owner_#{@ts}_#{@entropy}@test.com")
@org    = Onetime::Organization.create!("Img Corp #{@ts}", @owner, "img_org_#{@ts}@test.com")
@org.define_singleton_method(:billing_enabled?) { false }
@domain = Onetime::CustomDomain.create!("img-#{@ts}-#{@entropy}.example.com", @org.objid)
@extid  = @domain.extid

@strategy_result = MockStrategyResult.new(
  session: {},
  user: @owner,
  metadata: { organization_context: { organization: @org } },
)

# Build a Rack-multipart-shaped params hash: params['image'] is a Hash with a
# tempfile (StringIO here) + filename + type. process_params reads size/read
# off the tempfile.
def image_params(extid, content:, filename:, type:)
  {
    'extid' => extid,
    'image' => { 'tempfile' => StringIO.new(content), 'filename' => filename, 'type' => type },
  }
end

def build_icon(sr, params)
  DomainsAPI::Logic::Domains::UpdateDomainIcon.new(sr, params)
end

def build_logo(sr, params)
  DomainsAPI::Logic::Domains::UpdateDomainLogo.new(sr, params)
end

## Setup verification — domain exists and is owned by the org
[@domain.exists?, @domain.owner?(@owner)]
#=> [true, true]

## Case 1: UpdateDomainIcon widens the allowlist to the two .ico MIME types
[
  Icon.accepted_mime_types.include?('image/x-icon'),
  Icon.accepted_mime_types.include?('image/vnd.microsoft.icon'),
]
#=> [true, true]

## Case 2: UpdateDomainLogo's allowlist does NOT include the .ico types (unchanged)
[
  Logo.accepted_mime_types.include?('image/x-icon'),
  Logo.accepted_mime_types.include?('image/vnd.microsoft.icon'),
]
#=> [false, false]

## Case 3: both still accept the shared image types (e.g. png)
[Icon.accepted_mime_types.include?('image/png'), Logo.accepted_mime_types.include?('image/png')]
#=> [true, true]

## Case 4: the icon ceiling is 512KB; the logo keeps the 2MB shared default
[Icon.max_image_bytes, Logo.max_image_bytes]
#=> [512 * 1024, 2 * 1024 * 1024]

## Case 5: an ICO upload passes raise_concerns for the icon field (greenlit)
@icon_ico = build_icon(@strategy_result, image_params(@extid, content: 'AAAA', filename: 'favicon.ico', type: 'image/x-icon'))
@icon_ico.raise_concerns
@icon_ico.greenlighted
#=> true

## Case 6: the same ICO upload is rejected for the logo field ("Invalid file type")
@logo_ico = build_logo(@strategy_result, image_params(@extid, content: 'AAAA', filename: 'favicon.ico', type: 'image/x-icon'))
begin
  @logo_ico.raise_concerns
  'unexpected_success'
rescue Onetime::FormError => ex
  ex.message
end
#=> 'Invalid file type'

## Case 7: a 600KB upload exceeds the 512KB icon ceiling ("Image file is too large")
@big_content = 'x' * (600 * 1024)
@icon_big = build_icon(@strategy_result, image_params(@extid, content: @big_content, filename: 'big.png', type: 'image/png'))
begin
  @icon_big.raise_concerns
  'unexpected_success'
rescue Onetime::FormError => ex
  ex.message
end
#=> 'Image file is too large'

## Case 8: the same 600KB upload is fine for the logo field (under the 2MB ceiling)
@logo_big = build_logo(@strategy_result, image_params(@extid, content: @big_content, filename: 'big.png', type: 'image/png'))
@logo_big.raise_concerns
@logo_big.greenlighted
#=> true

## Case 9: FastImage guard — an unmeasurable icon (size -> nil) does NOT raise.
# Without the `height && !height.zero?` guard, `width.to_f / height` would raise
# on a nil height. process completes and returns the record hash.
FastImage.define_singleton_method(:size) { |*_args| nil }
@icon_nil = build_icon(@strategy_result, image_params(@extid, content: 'AAAA', filename: 'weird.ico', type: 'image/x-icon'))
@icon_nil.raise_concerns
@res_nil = @icon_nil.process
@res_nil[:record].is_a?(Hash)
#=> true

## Case 9b: the stored dimensions/ratio are unset (nil), not a bogus value
[@domain.icon['width'], @domain.icon['height'], @domain.icon['ratio']]
#=> [nil, nil, nil]

## Case 10: FastImage guard — a zero-height image ([16, 0]) skips the ratio
# division (no bogus Infinity) and still returns a record.
FastImage.define_singleton_method(:size) { |*_args| [16, 0] }
@icon_zero = build_icon(@strategy_result, image_params(@extid, content: 'AAAA', filename: 'weird2.ico', type: 'image/x-icon'))
@icon_zero.raise_concerns
@res_zero = @icon_zero.process
[@res_zero[:record].is_a?(Hash), @domain.icon['ratio']]
#=> [true, nil]

## Case 11: Regression (#3780) — an icon upload stamps favicon_source='user_upload'
# and drops any stale derived encoded_favicon cache so GetFavicon regenerates.
@domain.icon['encoded_favicon'] = 'STALE_DERIVED'
FastImage.define_singleton_method(:size) { |*_args| [32, 32] }
@icon_stamp = build_icon(@strategy_result, image_params(@extid, content: 'AAAA', filename: 'favicon.ico', type: 'image/x-icon'))
@icon_stamp.raise_concerns
@icon_stamp.process
[@domain.icon['favicon_source'], @domain.icon.hgetall.key?('encoded_favicon')]
#=> ['user_upload', false]

# --- Cleanup ---
FastImage.singleton_class.send(:remove_method, :size) if FastImage.singleton_methods.include?(:size)
@domain.destroy! if @domain&.exists?
@org.destroy! if @org&.exists?
@owner.destroy! if @owner&.exists?
Familia.dbclient.flushdb
OT.info 'Cleaned Redis after UpdateDomainImage test run'

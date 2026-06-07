# try/web/core/logic/page/get_favicon_try.rb
#
# frozen_string_literal: true

# Tests for Core::Logic::Page::GetFavicon#serve_custom_favicon.
#
# Regression anchor for the cached-favicon decode path. When a custom
# domain's icon (or logo) HashKey carries an 'encoded_favicon' value that
# is not valid Base64, the logic must NOT raise; it must fall back to
# generate_and_cache_favicon so the next response can rebuild the cache.
#
# Behaviors covered:
# 1. Corrupt cached Base64 falls back to generate_and_cache_favicon (no raise).
# 2. Valid cached Base64 populates @icon_data without regenerating.
# 3. Empty 'encoded_favicon' takes the existing "no cached version" path.

require_relative '../../../../../try/support/test_helpers'
require_relative '../../../../../try/support/test_models'

OT.boot! :test, false

require 'web/core/logic/page/get_favicon'

@timestamp = Familia.now.to_i
@owner     = Onetime::Customer.create!(email: "favicon_#{@timestamp}@test.com")
@org       = Onetime::Organization.create!("Favicon Org #{@timestamp}", @owner, "favicon_#{@timestamp}@test.com")
@domain    = Onetime::CustomDomain.create!("favicon-#{@timestamp}.example.com", @org.objid)

# Seed the icon hashkey with a filename so raise_concerns selects :icon as
# the image_source. The encoded_favicon field is filled in per-test.
@domain.icon['filename'] = 'icon.png'
@domain.icon['content_type'] = 'image/png'

# Build a logic instance bypassing process_params (which would try to load
# the custom domain by display_domain). Strategy_result uses a non-:custom
# domain_strategy so process_params leaves @custom_domain unset, then we
# inject @custom_domain and @image_source directly for the focused test.
def build_logic_for(domain)
  sess = MockSession.new
  metadata = { domain_strategy: :canonical, display_domain: 'example.com' }
  strategy_result = MockStrategyResult.new(
    session: sess,
    user: nil,
    auth_method: 'anonymous',
    metadata: metadata
  )
  logic = Core::Logic::Page::GetFavicon.new(strategy_result, {}, 'en')
  logic.instance_variable_set(:@custom_domain, domain)
  logic.instance_variable_set(:@image_source, :icon)
  logic.instance_variable_set(:@use_default, false)
  logic
end

## Corrupt cached Base64 does not raise and triggers regeneration
@domain.icon['encoded_favicon'] = '!!not-base64!!'
logic = build_logic_for(@domain)
@regen_called = false
logic.define_singleton_method(:generate_and_cache_favicon) do |_image_hash|
  @regen_called = true
  @icon_data = "regenerated-bytes"
end
# Re-bind the local closure so the singleton method can mutate the outer flag
logic.singleton_class.send(:define_method, :generate_and_cache_favicon) do |_image_hash|
  instance_variable_set(:@_regen_called, true)
  @icon_data = "regenerated-bytes"
end
begin
  logic.send(:serve_custom_favicon)
  [logic.instance_variable_get(:@_regen_called), logic.icon_data]
rescue ArgumentError => ex
  ["raised: #{ex.message}", nil]
end
#=> [true, "regenerated-bytes"]

## Valid cached Base64 populates @icon_data without calling generate_and_cache_favicon
@valid_payload = "valid-favicon-bytes"
@domain.icon['encoded_favicon'] = Base64.strict_encode64(@valid_payload)
logic = build_logic_for(@domain)
logic.singleton_class.send(:define_method, :generate_and_cache_favicon) do |_image_hash|
  instance_variable_set(:@_regen_called, true)
end
logic.send(:serve_custom_favicon)
[
  logic.instance_variable_get(:@_regen_called).nil?,
  logic.icon_data,
  logic.content_type,
]
#=> [true, "valid-favicon-bytes", "image/png"]

## Empty encoded_favicon takes the "no cached version" path (regression baseline)
@domain.icon['encoded_favicon'] = ''
logic = build_logic_for(@domain)
logic.singleton_class.send(:define_method, :generate_and_cache_favicon) do |_image_hash|
  instance_variable_set(:@_regen_called, true)
  @icon_data = "freshly-generated"
end
logic.send(:serve_custom_favicon)
[logic.instance_variable_get(:@_regen_called), logic.icon_data]
#=> [true, "freshly-generated"]

# Teardown
@domain.destroy!
@org.destroy!
@owner.destroy!

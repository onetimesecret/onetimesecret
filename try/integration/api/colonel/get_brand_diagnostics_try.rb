# try/integration/api/colonel/get_brand_diagnostics_try.rb
#
# frozen_string_literal: true

# Integration tests for the colonel brand-pack diagnostics endpoint (#3822):
#
#   GET /api/colonel/system/brand
#
# A read-only, colonel-only diagnostic that surfaces how the running instance
# resolved its brand pack (env vs frozen boot config vs live disk). It is a thin
# adapter over Onetime.brand_pack_diagnostics — the single source of truth also
# used by `bin/ots config brand`. This file exercises the wire contract, not the
# resolution logic (that is covered where the module method lives). Covers:
# - 403 non-colonel, 401 anonymous
# - 200 colonel + the full top-level shape of the `details` payload
#
# Run: try --agent try/integration/api/colonel/get_brand_diagnostics_try.rb

require 'rack/test'
require_relative '../../../support/test_helpers'

OT.boot! :test

require 'onetime/application/registry'
Onetime::Application::Registry.prepare_application_registry

@test = Object.new
@test.extend Rack::Test::Methods

def @test.app
  Onetime::Application::Registry.generate_rack_url_map
end

def get(*args);    @test.get(*args);    end
def last_response; @test.last_response; end

@timestamp = Familia.now.to_i

@colonel = Onetime::Customer.create!(email: "colonel_gbd_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

@regular = Onetime::Customer.create!(email: "regular_gbd_#{@timestamp}@example.com")
@regular.verified = 'true'
@regular.save

@colonel_session = {
  'authenticated' => true, 'external_id' => @colonel.extid, 'email' => @colonel.email,
}
@regular_session = {
  'authenticated' => true, 'external_id' => @regular.extid, 'email' => @regular.email,
}

def colonel_headers
  { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
end

URL = '/api/colonel/system/brand'

# ----------------------------------------------------------------
# Authorization
# ----------------------------------------------------------------

## Non-colonel gets 403
get URL, {}, { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

## Anonymous gets 401
@test.clear_cookies
get URL, {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

# ----------------------------------------------------------------
# Colonel: 200 + payload shape
# ----------------------------------------------------------------

## Colonel session gets 200 with a details payload
get URL, {}, colonel_headers
@resp = JSON.parse(last_response.body)
[last_response.status, @resp['details'].is_a?(Hash)]
#=> [200, true]

## details carries every top-level brand-diagnostic key
@resp = JSON.parse(last_response.body)
d = @resp['details']
%w[home env config roots resolved_dir fell_back_to_default manifest boot_vs_live_mismatch overlay_assets].all? { |k| d.key?(k) }
#=> true

## headline flags are real JSON booleans; roots / overlay_assets are arrays
@resp = JSON.parse(last_response.body)
d = @resp['details']
[[true, false].include?(d['fell_back_to_default']),
 [true, false].include?(d['boot_vs_live_mismatch']),
 d['roots'].is_a?(Array),
 d['overlay_assets'].is_a?(Array)]
#=> [true, true, true, true]

## nested env / config / manifest sub-shapes are present
@resp = JSON.parse(last_response.body)
d = @resp['details']
[d['env'].key?('brand_pack'),
 d['config'].key?('brand_absorbed'),
 d['config'].key?('brand_operator_keys'),
 d['manifest'].key?('keys_on_disk')]
#=> [true, true, true, true]

## record is an empty object (success_data does not run the custid->user_id transform)
@resp = JSON.parse(last_response.body)
@resp['record']
#=> {}

# ----------------------------------------------------------------
# Teardown (no OT.conf mutation in this file; only remove test customers)
# ----------------------------------------------------------------
@colonel.destroy!  rescue nil
@regular.destroy!  rescue nil

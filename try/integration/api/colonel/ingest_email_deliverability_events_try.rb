# try/integration/api/colonel/ingest_email_deliverability_events_try.rb
#
# frozen_string_literal: true

# Route-level authorization guard for the colonel deliverability-ingest verb:
#
#   POST /api/colonel/email/deliverability/events  ->  IngestEmailDeliverabilityEvents
#
# This endpoint is DELIBERATELY NOT a public webhook (see the logic class
# docstring, epic #20): an unauthenticated bounce receiver would let anyone
# suppress a victim's address. Both authorization layers must reject a
# non-colonel BEFORE any ingest happens:
#
#   - anonymous                  -> 401  (router auth=sessionauth, no session)
#   - authenticated non-colonel  -> 403  (router role=colonel gate)
#
# A colonel request gets PAST both gates and lands on the logic's own form
# validation (422 for an empty/absent events array). That case proves the
# route actually resolves and the 401/403 above are genuine auth rejections,
# not a 404 in disguise.
#
# The whole-surface enumeration lives in bfla_colonel_authz_try.rb; this file
# pins the invariant explicitly for the security-sensitive ingest verb.
#
# Run: try --agent try/integration/api/colonel/ingest_email_deliverability_events_try.rb

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

def post(*args);   @test.post(*args);   end
def last_response; @test.last_response; end

@timestamp = Familia.now.to_i

@colonel = Onetime::Customer.create!(email: "colonel_iede_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

@regular = Onetime::Customer.create!(email: "regular_iede_#{@timestamp}@example.com")
@regular.verified = 'true'
@regular.save

@colonel_session = {
  'authenticated' => true,
  'external_id'   => @colonel.extid,
  'email'         => @colonel.email,
}
@regular_session = {
  'authenticated' => true,
  'external_id'   => @regular.extid,
  'email'         => @regular.email,
}

URL = '/api/colonel/email/deliverability/events'

# ----------------------------------------------------------------
# Authorization perimeter (route-level, through the real router)
# ----------------------------------------------------------------

## Anonymous request is rejected with 401 — never publicly reachable
@test.clear_cookies
post URL, {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

## Authenticated NON-colonel is rejected with 403 (router role=colonel gate)
@test.clear_cookies
post URL, {}, { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

## A colonel clears both gates and reaches form validation (422 on empty
## events) — proving the route resolves and the 401/403 above are auth
## rejections, not a routing miss.
@test.clear_cookies
post URL, {}, { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 422

# ----------------------------------------------------------------
# Teardown
# ----------------------------------------------------------------
@colonel.destroy! rescue nil
@regular.destroy! rescue nil

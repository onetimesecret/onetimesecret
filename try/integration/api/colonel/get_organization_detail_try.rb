# try/integration/api/colonel/get_organization_detail_try.rb
#
# frozen_string_literal: true

# Integration tests for the colonel organization detail + reconcile endpoints:
#
#   GET  /api/colonel/organizations/:org_id
#   POST /api/colonel/organizations/:org_id/reconcile
#
# Covers:
# - 403 for non-colonel, 401 for anonymous, 404 for non-existent org
# - Detail record shape incl. FULL (unmasked) emails — the admin UI obscures
#   client-side and reveals on interaction, so the payload carries the real
#   address (RevealEmail.vue)
# - Entitlement state block: plan / grants / revokes / materialized / expected
#   / drift — the gap this endpoint closes (the list carried no entitlements)
# - Members roster with role + owner flag; domains roster is an array
# - extid-first org resolution
# - Reconcile (entitlements-only path, no Stripe subscription): 200, mode,
#   before/after diff, and one audit event
#
# Run: try --agent try/integration/api/colonel/get_organization_detail_try.rb

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

def post(*args);   @test.post(*with_csrf(args));   end
def get(*args);    @test.get(*args);    end
def last_response; @test.last_response; end

# ----------------------------------------------------------------
# Test data setup
# ----------------------------------------------------------------

@timestamp = Familia.now.to_i

@colonel = Onetime::Customer.create!(email: "colonel_od_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

@regular = Onetime::Customer.create!(email: "regular_od_#{@timestamp}@example.com")
@regular.verified = 'true'
@regular.save

@org_owner = Onetime::Customer.create!(email: "org_owner_od_#{@timestamp}@example.com")
@org_owner.verified = 'true'
@org_owner.save

@org = Onetime::Organization.create!("Org Detail Test Org #{@timestamp}", @org_owner, "billing_od_#{@timestamp}@example.com")

# Materialize a baseline plan set + one operator grant so the entitlement block
# has plan-derived AND override-derived members to distinguish.
@org.entitlements_plan.add('api_access')
@org.entitlements_plan.add('create_secrets')
@org.materialized_entitlements_at = "#{@timestamp}:baseline"
@org.apply_entitlements
@org.grant_entitlement('custom_domains')
@org.save

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

def colonel_headers
  { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
end

# ----------------------------------------------------------------
# Authorization
# ----------------------------------------------------------------

## Non-colonel gets 403 on detail
get "/api/colonel/organizations/#{@org.extid}",
  {}, { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

## Anonymous gets 401 on detail
@test.clear_cookies
get "/api/colonel/organizations/#{@org.extid}", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

## Colonel gets 404 for a non-existent org
get "/api/colonel/organizations/nonexistent_#{@timestamp}", {}, colonel_headers
[last_response.status, JSON.parse(last_response.body).key?('error')]
#=> [404, true]

# ----------------------------------------------------------------
# Detail record
# ----------------------------------------------------------------

## Detail: 200 with record + details envelope
get "/api/colonel/organizations/#{@org.extid}", {}, colonel_headers
@resp = JSON.parse(last_response.body)
[last_response.status, @resp.key?('record'), @resp.key?('details')]
#=> [200, true, true]

## Detail: record carries billing + identity fields
@resp = JSON.parse(last_response.body)
r = @resp['record']
[r['extid'] == @org.extid, r.key?('planid'), r.key?('sync_status'), r.key?('member_count'), r.key?('domain_count')]
#=> [true, true, true, true, true]

## Detail: contact_email is the FULL address (not obscured — create!'s 3rd arg)
@resp = JSON.parse(last_response.body)
@resp['record']['contact_email']
#=> "billing_od_#{@timestamp}@example.com"

## Detail: owner_email is the FULL owner address (no bullets)
@resp = JSON.parse(last_response.body)
@resp['record']['owner_email'].to_s.include?('•')
#=> false

# ----------------------------------------------------------------
# Entitlement state block
# ----------------------------------------------------------------

## Entitlements: exposes plan / grants / revokes / materialized / expected / drift
@resp = JSON.parse(last_response.body)
e = @resp['details']['entitlements']
%w[plan grants revokes materialized expected materialized_flag drift].all? { |k| e.key?(k) }
#=> true

## Entitlements: plan set contains the two plan-derived entitlements
@resp = JSON.parse(last_response.body)
e = @resp['details']['entitlements']
[e['plan'].include?('api_access'), e['plan'].include?('create_secrets')]
#=> [true, true]

## Entitlements: the operator grant appears in grants AND in materialized
@resp = JSON.parse(last_response.body)
e = @resp['details']['entitlements']
[e['grants'].include?('custom_domains'), e['materialized'].include?('custom_domains')]
#=> [true, true]

## Entitlements: materialized == expected and drift.in_sync (no orphans)
@resp = JSON.parse(last_response.body)
e = @resp['details']['entitlements']
[e['materialized'].sort == e['expected'].sort, e['drift']['in_sync']]
#=> [true, true]

# ----------------------------------------------------------------
# Members + domains rosters
# ----------------------------------------------------------------

## Members: is an array; each row has the expected keys
@resp = JSON.parse(last_response.body)
members = @resp['details']['members']
members.is_a?(Array) && (members.empty? || %w[extid email role is_owner].all? { |k| members.first.key?(k) })
#=> true

## Domains: is an array
@resp = JSON.parse(last_response.body)
@resp['details']['domains'].is_a?(Array)
#=> true

# ----------------------------------------------------------------
# Reconcile (entitlements-only: org has no Stripe subscription)
# ----------------------------------------------------------------

## Reconcile: 200 with mode=entitlements_only + before/after diff
@before_count = Onetime::AdminAuditEvent.count
post "/api/colonel/organizations/#{@org.extid}/reconcile", {}, colonel_headers
@resp = JSON.parse(last_response.body)
rec = @resp['record']
[last_response.status, rec['mode'], rec.key?('before'), rec.key?('after')]
#=> [200, 'entitlements_only', true, true]

## Reconcile: records exactly one audit event with the reconcile verb + org target
@evt = Onetime::AdminAuditEvent.recent(1).first
[
  Onetime::AdminAuditEvent.count - @before_count,
  @evt['verb'],
  @evt['actor'] == @colonel.extid,
  @evt['target'] == @org.extid,
  @evt['result'],
]
#=> [1, 'organization.reconcile', true, true, 'success']

## Reconcile: non-colonel gets 403
post "/api/colonel/organizations/#{@org.extid}/reconcile",
  {}, { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

# ----------------------------------------------------------------
# Teardown
# ----------------------------------------------------------------
@org.destroy!       rescue nil
@org_owner.destroy! rescue nil
@colonel.destroy!   rescue nil
@regular.destroy!   rescue nil

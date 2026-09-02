# try/integration/api/colonel/admin_ops_expansion_try.rb
#
# frozen_string_literal: true

# Integration tests for the colonel admin-ops expansion:
#
#   POST /api/colonel/organizations/:org_id/members  (AddMembership by EMAIL)
#   GET  /api/colonel/users/:user_id                 (GetUserDetails by EMAIL)
#   GET  /api/colonel/domains?search=&status=&org_id= (ListCustomDomains filters)
#   GET  /api/colonel/billing/stripe-organizations   (ListStripeOrganizations)
#
# Covers:
# - The email-identifier bug: sanitize_identifier stripped '@' and '.', so every
#   documented "email or extid" colonel identifier resolved to nothing. The
#   membership + user surfaces now accept an email.
# - AddMembership stays additive (:no_change on a repeat) and audits exactly
#   one membership.add event for a real add, plus one outcome: 'no_change'
#   event under the same verb for a repeat attempt (#4337).
# - ListCustomDomains' new server-side filters narrow total_count BEFORE
#   pagination, and an unfiltered call is unchanged.
# - The Stripe roster is index-backed: it finds an org by its Stripe customer
#   id, honours the server-side search glob, counts (but does not render) stale
#   index entries, and writes NO audit event (it is a read).
# - 401 anonymous / 403 non-colonel on the new route.
#
# Run: try --agent try/integration/api/colonel/admin_ops_expansion_try.rb

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

@colonel = Onetime::Customer.create!(email: "colonel_aox_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

@regular = Onetime::Customer.create!(email: "regular_aox_#{@timestamp}@example.com")
@regular.verified = 'true'
@regular.save

@org_owner = Onetime::Customer.create!(email: "owner_aox_#{@timestamp}@example.com")
@org_owner.verified = 'true'
@org_owner.save

# The account we will add to the org BY EMAIL (the bug this exercises).
@joiner       = Onetime::Customer.create!(email: "joiner_aox_#{@timestamp}@example.com")
@joiner.verified = 'true'
@joiner.save
@joiner_email = @joiner.email
@joiner_extid = @joiner.extid

@org = Onetime::Organization.create!("AOX Org #{@timestamp}", @org_owner, "billing_aox_#{@timestamp}@example.com")

# A second org carrying a Stripe customer id, for the billing roster.
@billed_org = Onetime::Organization.create!("AOX Billed #{@timestamp}", @org_owner)
@stripe_customer_id = "cus_AOX#{@timestamp}"
@billed_org.stripe_customer_id = @stripe_customer_id
@billed_org.planid = 'identity_v1'
@billed_org.subscription_status = 'active'
@billed_org.billing_email = "stripe_aox_#{@timestamp}@example.com"
@billed_org.save

# A deliberately stale index entry: field present, org gone.
@stale_stripe_id = "cus_AOXSTALE#{@timestamp}"
Onetime::Organization.stripe_customer_id_index[@stale_stripe_id] = "gone_#{@timestamp}"

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

def colonel_get_headers
  { 'rack.session' => @colonel_session, 'HTTP_ACCEPT' => 'application/json' }
end

# ----------------------------------------------------------------
# AddMembership by EMAIL (the sanitize_identifier bug)
# ----------------------------------------------------------------

## An email survives sanitization and resolves to the account (200, not 404)
@before_audit = Onetime::ColonelAuditEvent.count
post "/api/colonel/organizations/#{@org.extid}/members",
  { 'customer' => @joiner_email, 'role' => 'admin' }, colonel_headers
@add_resp = JSON.parse(last_response.body)
[last_response.status, @add_resp['record']['status'], @add_resp['record']['role']]
#=> [200, "success", "admin"]

## The member_id echoed back is the account's PUBLIC id, never an email
@add_resp['record']['member_id'] == @joiner_extid
#=> true

## The membership really exists on the org
Onetime::Organization.find_by_extid(@org.extid).member?(Onetime::Customer.find_by_extid(@joiner_extid))
#=> true

## Exactly one membership.add audit event was recorded (by the op, not the adapter)
@after_audit = Onetime::ColonelAuditEvent.count
@latest = Onetime::ColonelAuditEvent.recent(1, 0).first
[@after_audit - @before_audit, @latest['verb'], @latest['actor']]
#=> [1, "membership.add", @colonel.extid]

## Add is strictly additive: a repeat by email is :no_change, still audited (#4337)
@before_audit2 = Onetime::ColonelAuditEvent.count
post "/api/colonel/organizations/#{@org.extid}/members",
  { 'customer' => @joiner_email, 'role' => 'member' }, colonel_headers
@again = JSON.parse(last_response.body)
[last_response.status, @again['record']['status'], @again['record']['role'],
 Onetime::ColonelAuditEvent.count - @before_audit2]
#=> [200, "no_change", "admin", 1]

## The repeat lands under the same verb, marked outcome: no_change, with the CURRENT role
@noop_event = Onetime::ColonelAuditEvent.recent(1, 0).first
[@noop_event['verb'], @noop_event['result'], @noop_event['detail']]
#=> ["membership.add", "success", { "outcome" => "no_change", "role" => "admin", "org_id" => @org.extid }]

## An unknown email is a clean 404, not a 500
post "/api/colonel/organizations/#{@org.extid}/members",
  { 'customer' => "nobody_#{@timestamp}@example.com" }, colonel_headers
last_response.status
#=> 404

## An email with HTML/control junk is stripped, not executed (still a 404)
post "/api/colonel/organizations/#{@org.extid}/members",
  { 'customer' => "<script>x</script>nobody_#{@timestamp}@example.com" }, colonel_headers
last_response.status < 500
#=> true

# ----------------------------------------------------------------
# GetUserDetails by EMAIL
# ----------------------------------------------------------------

## The user detail read resolves an email identifier too
get "/api/colonel/users/#{CGI.escape(@joiner_email)}", {}, colonel_get_headers
@detail = JSON.parse(last_response.body)
[last_response.status, @detail['record']['extid']]
#=> [200, @joiner_extid]

## ...and still resolves the extid (the path every admin surface routes by)
get "/api/colonel/users/#{@joiner_extid}", {}, colonel_get_headers
[last_response.status, JSON.parse(last_response.body)['record']['extid']]
#=> [200, @joiner_extid]

# ----------------------------------------------------------------
# ListCustomDomains filters
# ----------------------------------------------------------------

## Create a domain to filter on
@aox_domain = "aox-#{@timestamp}.example.com"
post '/api/colonel/domains', { 'org_id' => @org.extid, 'domain' => @aox_domain }, colonel_headers
@created_domain = JSON.parse(last_response.body)['record']
[last_response.status, @created_domain['display_domain']]
#=> [200, @aox_domain]

## Unfiltered list still answers with the incumbent envelope
get '/api/colonel/domains', {}, colonel_get_headers
@list = JSON.parse(last_response.body)
[last_response.status, @list['details'].key?('domains'), @list['details'].key?('pagination')]
#=> [200, true, true]

## search narrows total_count BEFORE pagination
get '/api/colonel/domains', { 'search' => "aox-#{@timestamp}" }, colonel_get_headers
@filtered = JSON.parse(last_response.body)
[last_response.status,
 @filtered['details']['pagination']['total_count'],
 @filtered['details']['domains'].first['display_domain']]
#=> [200, 1, @aox_domain]

## The applied filters are echoed back under details.filters
@filtered['details']['filters']['search']
#=> "aox-#{@timestamp}"

## org_id accepts the org EXTID (not just the internal objid it stores)
get '/api/colonel/domains', { 'org_id' => @org.extid }, colonel_get_headers
@by_org = JSON.parse(last_response.body)
@by_org['details']['domains'].all? { |d| d['display_domain'].include?("aox-#{@timestamp}") }
#=> true

## A non-matching search yields an empty page, not an error
get '/api/colonel/domains', { 'search' => "nothing-matches-#{@timestamp}" }, colonel_get_headers
@empty = JSON.parse(last_response.body)
[last_response.status, @empty['details']['pagination']['total_count'], @empty['details']['domains']]
#=> [200, 0, []]

# ----------------------------------------------------------------
# ListStripeOrganizations — authorization
# ----------------------------------------------------------------

## Anonymous gets 401 on the Stripe roster
@test.clear_cookies
get '/api/colonel/billing/stripe-organizations', {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

## Non-colonel gets 403
get '/api/colonel/billing/stripe-organizations', {},
  { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

# ----------------------------------------------------------------
# ListStripeOrganizations — payload
# ----------------------------------------------------------------

## 200 with the record/details envelope and the documented detail keys
get '/api/colonel/billing/stripe-organizations', {}, colonel_get_headers
@roster = JSON.parse(last_response.body)
[last_response.status,
 %w[organizations pagination filters capped stale_count indexed_total]
   .all? { |k| @roster['details'].key?(k) }]
#=> [200, true]

## The server-side glob finds the seeded org by its Stripe customer id
get '/api/colonel/billing/stripe-organizations', { 'search' => "AOX#{@timestamp}" }, colonel_get_headers
@hit = JSON.parse(last_response.body)['details']['organizations']
[@hit.size, @hit.first['extid'], @hit.first['stripe_customer_id']]
#=> [1, @billed_org.extid, @stripe_customer_id]

## Rows carry the billing fields the admin table renders
@row = @hit.first
%w[org_id extid display_name owner_email billing_email planid stripe_customer_id
   stripe_subscription_id subscription_status subscription_period_end sync_status]
  .all? { |k| @row.key?(k) }
#=> true

## A stale index entry is counted, never rendered as a row with a blank extid
get '/api/colonel/billing/stripe-organizations', { 'search' => "AOXSTALE#{@timestamp}" }, colonel_get_headers
@stale = JSON.parse(last_response.body)['details']
[@stale['organizations'], @stale['stale_count'], @stale['pagination']['total_count']]
#=> [[], 1, 1]

## The roster is READ-ONLY: it writes no ColonelAuditEvent
@before_read = Onetime::ColonelAuditEvent.count
get '/api/colonel/billing/stripe-organizations', {}, colonel_get_headers
Onetime::ColonelAuditEvent.count - @before_read
#=> 0

## per_page is clamped to 100 even when the caller asks for more
get '/api/colonel/billing/stripe-organizations', { 'per_page' => '5000' }, colonel_get_headers
JSON.parse(last_response.body)['details']['pagination']['per_page']
#=> 100

# ----------------------------------------------------------------
# Teardown
# ----------------------------------------------------------------

Onetime::Organization.stripe_customer_id_index.remove(@stale_stripe_id)
Onetime::CustomDomain.load_by_display_domain(@aox_domain)&.destroy!
@billed_org.destroy!
@org.destroy!
@joiner.destroy!
@org_owner.destroy!
@regular.destroy!
@colonel.destroy!

# try/integration/api/colonel/custom_domain_attach_try.rb
#
# frozen_string_literal: true

# Integration tests for the colonel custom-domain attach + detail endpoints:
#
#   POST /api/colonel/domains          (CreateCustomDomain)
#   GET  /api/colonel/domains/:extid   (GetCustomDomain)
#
# Covers:
# - 401 anonymous, 403 non-colonel on both verbs
# - Create: 404 for a non-existent org, 4xx form error for an invalid domain
# - Create attaches the domain to ANY org by extid with NO membership gate
# - Response envelope { record, details.cluster } and the DNS fields the admin
#   panel renders — including the three merged-in fields safe_dump omits
#   (verification_state / resolving / ready), typed to match VerifyCustomDomain
# - Exactly one AdminAuditEvent per create: verb=domain.create,
#   target=domain.extid, actor=colonel.extid
# - Duplicate create is a clean 4xx (pre-checked), not a 500
# - Detail: 200 by extid with the same shape, 404 for unknown extid
#
# Run: try --agent try/integration/api/colonel/custom_domain_attach_try.rb

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
def get(*args);    @test.get(*args);    end
def last_response; @test.last_response; end

# ----------------------------------------------------------------
# Test data setup
# ----------------------------------------------------------------

@timestamp = Familia.now.to_i

@colonel = Onetime::Customer.create!(email: "colonel_cd_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

@regular = Onetime::Customer.create!(email: "regular_cd_#{@timestamp}@example.com")
@regular.verified = 'true'
@regular.save

@org_owner = Onetime::Customer.create!(email: "org_owner_cd_#{@timestamp}@example.com")
@org_owner.verified = 'true'
@org_owner.save

# Colonel is NOT a member of this org — the whole point of the endpoint.
@org = Onetime::Organization.create!("CD Attach Org #{@timestamp}", @org_owner, "billing_cd_#{@timestamp}@example.com")

@domain     = "colonel-cd-#{@timestamp}.example.com"
@domain_dup = @domain

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
# Authorization — POST /domains
# ----------------------------------------------------------------

## Anonymous gets 401 on create
@test.clear_cookies
post '/api/colonel/domains', { 'org_id' => @org.extid, 'domain' => @domain }, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

## Non-colonel gets 403 on create
post '/api/colonel/domains', { 'org_id' => @org.extid, 'domain' => @domain },
  { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

# ----------------------------------------------------------------
# Create — validation + resolution
# ----------------------------------------------------------------

## Create: 404 for a non-existent org
post '/api/colonel/domains', { 'org_id' => "nonexistent_#{@timestamp}", 'domain' => @domain }, colonel_headers
[last_response.status, JSON.parse(last_response.body).key?('error')]
#=> [404, true]

## Create: invalid domain is a 4xx form error, not a 500
post '/api/colonel/domains', { 'org_id' => @org.extid, 'domain' => 'not-a-valid-domain' }, colonel_headers
last_response.status < 500
#=> true

## Create: 200 with { record, details } envelope
@before_count = Onetime::AdminAuditEvent.count
post '/api/colonel/domains', { 'org_id' => @org.extid, 'domain' => @domain }, colonel_headers
@resp = JSON.parse(last_response.body)
[last_response.status, @resp.key?('record'), @resp.key?('details')]
#=> [200, true, true]

## Create: record carries the identity + DNS fields the admin panel renders
@resp = JSON.parse(last_response.body)
r = @resp['record']
%w[domain_id extid display_domain base_domain trd is_apex txt_validation_host txt_validation_value created updated verified].all? { |k| r.key?(k) }
#=> true

## Create: domain_id is the domain's own id, not safe_dump's un-underscored `domainid` alias
@resp = JSON.parse(last_response.body)
r = @resp['record']
r['domain_id'] == Onetime::CustomDomain.find_by_extid(r['extid']).domainid
#=> true

## Create: the three DNS fields safe_dump OMITS are merged in
@resp = JSON.parse(last_response.body)
r = @resp['record']
%w[verification_state resolving ready].all? { |k| r.key?(k) }
#=> true

## Create: fresh domain reports pending / not-resolving / not-ready / unverified
@resp = JSON.parse(last_response.body)
r = @resp['record']
[r['verification_state'], r['resolving'], r['ready'], r['verified']]
#=> ['pending', false, false, false]

## Create: display_domain echoes the requested host
@resp = JSON.parse(last_response.body)
@resp['record']['display_domain']
#=> @domain

## Create: details.cluster is present
@resp = JSON.parse(last_response.body)
@resp['details'].key?('cluster')
#=> true

## Create: domain is attached to the target org (no membership gate)
@org.domain_count
#=> 1

## Create: records exactly one audit event — verb=domain.create, target=domain extid
@created_extid = JSON.parse(last_response.body)['record']['extid']
@evt = Onetime::AdminAuditEvent.recent(1).first
[
  Onetime::AdminAuditEvent.count - @before_count,
  @evt['verb'],
  @evt['actor'] == @colonel.extid,
  @evt['target'] == @created_extid,
  @evt['result'],
]
#=> [1, 'domain.create', true, true, 'success']

## Create: duplicate attach to same org is a clean 4xx (not 500)
post '/api/colonel/domains', { 'org_id' => @org.extid, 'domain' => @domain_dup }, colonel_headers
[last_response.status >= 400, last_response.status < 500]
#=> [true, true]

# ----------------------------------------------------------------
# Detail — GET /domains/:extid
# ----------------------------------------------------------------

## Detail: anonymous gets 401
@test.clear_cookies
get "/api/colonel/domains/#{@created_extid}", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

## Detail: non-colonel gets 403
get "/api/colonel/domains/#{@created_extid}", {},
  { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

## Detail: colonel gets 404 for an unknown extid
get "/api/colonel/domains/cd_nonexistent_#{@timestamp}", {}, colonel_headers
[last_response.status, JSON.parse(last_response.body).key?('error')]
#=> [404, true]

## Detail: 200 with the SAME shape as create (record + details.cluster)
get "/api/colonel/domains/#{@created_extid}", {}, colonel_headers
@resp = JSON.parse(last_response.body)
r = @resp['record']
[
  last_response.status,
  r['extid'] == @created_extid,
  r['display_domain'] == @domain,
  r.key?('domain_id'),
  %w[verification_state resolving ready].all? { |k| r.key?(k) },
  @resp['details'].key?('cluster'),
]
#=> [200, true, true, true, true, true]

# ----------------------------------------------------------------
# Teardown
# ----------------------------------------------------------------
Onetime::CustomDomain.find_by_extid(@created_extid)&.destroy! rescue nil
@org.destroy!       rescue nil
@org_owner.destroy! rescue nil
@colonel.destroy!   rescue nil
@regular.destroy!   rescue nil

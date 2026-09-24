# try/integration/api/colonel/domain_configs_try.rb
#
# frozen_string_literal: true

# Integration tests for the colonel per-domain config endpoints:
#
#   GET    /api/colonel/domains/:extid/configs           (GetDomainConfigs)
#   POST   /api/colonel/domains/:extid/configs/ensure    (EnsureDomainConfigs)
#   PUT    /api/colonel/domains/:extid/configs/:kind     (UpsertDomainConfig)
#   DELETE /api/colonel/domains/:extid/configs/:kind     (DeleteDomainConfig)
#
# Covers:
# - 401 anonymous / 403 non-colonel on GET configs
# - GET on a fresh domain: homepage+api exist (bootstrapped on domain create),
#   the other five report exists:false, config:null
# - ensure dry-run DEFAULT (no body): plans signin/signup/incoming, mutates and
#   audits NOTHING
# - ensure apply: creates the three missing kinds disabled, reports
#   homepage/api as existing, always skips sso+mailer (requires_credentials),
#   records EXACTLY ONE domain.configs_ensure audit event
# - PUT signin: partial update with real-boolean response + one
#   domain.config_upsert audit event carrying changed field NAMES; create path
#   (outcome=created) on a second domain
# - PUT invalid enum -> 422 form error, no audit; PUT sso -> 422 not editable
# - PUT signup allowed_signup_domains: model-setter validation surfaces as a
#   4xx form error; valid arrays round-trip
# - DELETE: one domain.config_delete audit event; repeat delete -> 404;
#   sso records are deletable too
# - Redaction: an SsoConfig with real client_id/client_secret and a
#   MailerConfig with a real api_key serialize presence booleans only — the
#   raw response body NEVER contains a credential value
# - Unknown kind -> 404; unknown domain extid -> 404
#
# Run: try --agent try/integration/api/colonel/domain_configs_try.rb

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
def put(*args);    @test.put(*with_csrf(args));    end
def delete(*args); @test.delete(*with_csrf(args)); end
def get(*args);    @test.get(*args);    end
def last_response; @test.last_response; end

# ----------------------------------------------------------------
# Test data setup
# ----------------------------------------------------------------

@timestamp = Familia.now.to_i

@colonel = Onetime::Customer.create!(email: "colonel_dc_#{@timestamp}@example.com")
@colonel.role = 'colonel'
@colonel.verified = 'true'
@colonel.save

@regular = Onetime::Customer.create!(email: "regular_dc_#{@timestamp}@example.com")
@regular.verified = 'true'
@regular.save

@org_owner = Onetime::Customer.create!(email: "owner_dc_#{@timestamp}@example.com")
@org_owner.verified = 'true'
@org_owner.save

@org = Onetime::Organization.create!("DC Org #{@timestamp}", @org_owner, "billing_dc_#{@timestamp}@example.com")

# CustomDomain.create! bootstraps HomepageConfig + ApiConfig (the per-domain
# config invariant); the other five kinds start absent.
@domain  = Onetime::CustomDomain.create!("colonel-dc-#{@timestamp}.example.com", @org.objid)
@domain2 = Onetime::CustomDomain.create!("colonel-dc2-#{@timestamp}.example.com", @org.objid)
@extid   = @domain.extid
@extid2  = @domain2.extid

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

# Server-side destructive-action confirmation (#4326): the config upsert (TIER 2)
# and delete (TIER 1) verbs require "<display_domain>:<kind>", percent-encoded,
# in X-OTS-Confirm — the URL carries only the extid. `ensure` is TIER 3
# (idempotent backfill of missing rows) and needs nothing.
def confirming_config(domain, kind)
  colonel_headers.merge(
    'HTTP_X_OTS_CONFIRM' => Rack::Utils.escape("#{domain.display_domain}:#{kind}"),
  )
end

# ----------------------------------------------------------------
# Authorization — GET /domains/:extid/configs
# ----------------------------------------------------------------

## Anonymous gets 401 on GET configs
@test.clear_cookies
get "/api/colonel/domains/#{@extid}/configs", {}, { 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 401

## Non-colonel gets 403 on GET configs
get "/api/colonel/domains/#{@extid}/configs", {},
  { 'rack.session' => @regular_session, 'HTTP_ACCEPT' => 'application/json' }
last_response.status
#=> 403

# ----------------------------------------------------------------
# GET — fresh domain baseline
# ----------------------------------------------------------------

## GET: 200 with the { record, details.configs } envelope and all seven kinds
get "/api/colonel/domains/#{@extid}/configs", {}, colonel_headers
@resp = JSON.parse(last_response.body)
[last_response.status, @resp['record']['extid'], @resp['details']['configs'].keys.sort]
#=> [200, @extid, %w[api homepage incoming mailer signin signup sso]]

## GET: record carries domain_id + display_domain (the TransferDomain record shape)
r = @resp['record']
[r['domain_id'] == @domain.domainid, r['display_domain']]
#=> [true, @domain.display_domain]

## GET: homepage + api were bootstrapped on domain create and report disabled
c = @resp['details']['configs']
[c['homepage']['exists'], c['homepage']['config']['enabled'],
 c['api']['exists'], c['api']['config']['enabled']]
#=> [true, false, true, false]

## GET: homepage serialization EXCLUDES the deprecated read-echo auth-link fields (ADR-030)
hp = @resp['details']['configs']['homepage']['config']
[hp.key?('signup_enabled'), hp.key?('signin_enabled'), hp['secrets_mode']]
#=> [false, false, 'create']

## GET: the other five kinds are absent — exists:false, config:null
%w[signin signup incoming sso mailer].map { |k| [@resp['details']['configs'][k]['exists'], @resp['details']['configs'][k]['config']] }
#=> [[false, nil], [false, nil], [false, nil], [false, nil], [false, nil]]

# ----------------------------------------------------------------
# POST ensure — dry-run default (no body)
# ----------------------------------------------------------------

## ensure with NO body defaults to dry_run=true and plans the three missing kinds
@before_audit = Onetime::ColonelAuditEvent.count
post "/api/colonel/domains/#{@extid}/configs/ensure", {}, colonel_headers
@resp = JSON.parse(last_response.body)
d = @resp['details']
[last_response.status, d['dry_run'], d['created'].sort, d['existing'].sort]
#=> [200, true, %w[incoming signin signup], %w[api homepage]]

## ensure dry-run mutates NOTHING and audits NOTHING
[
  Onetime::ColonelAuditEvent.count - @before_audit,
  Onetime::CustomDomain::SigninConfig.exists_for_domain?(@domain.identifier),
  Onetime::CustomDomain::SignupConfig.exists_for_domain?(@domain.identifier),
  Onetime::CustomDomain::IncomingConfig.exists_for_domain?(@domain.identifier),
]
#=> [0, false, false, false]

# ----------------------------------------------------------------
# POST ensure — apply
# ----------------------------------------------------------------

## ensure apply creates the missing kinds and skips sso+mailer with a reason
@before_audit = Onetime::ColonelAuditEvent.count
post "/api/colonel/domains/#{@extid}/configs/ensure", { 'dry_run' => 'false' }, colonel_headers
@resp = JSON.parse(last_response.body)
d = @resp['details']
[last_response.status, d['dry_run'], d['created'].sort, d['existing'].sort, d['skipped']]
#=> [200, false, %w[incoming signin signup], %w[api homepage], [{'kind' => 'sso', 'reason' => 'requires_credentials'}, {'kind' => 'mailer', 'reason' => 'requires_credentials'}]]

## ensure apply records EXACTLY ONE domain.configs_ensure audit event
@after_audit = Onetime::ColonelAuditEvent.count
@latest = Onetime::ColonelAuditEvent.recent(1, 0).first
[@after_audit - @before_audit, @latest['verb'], @latest['actor']]
#=> [1, "domain.configs_ensure", @colonel.extid]

## ensure apply materialized the records DISABLED (behavior-neutral)
[
  Onetime::CustomDomain::SigninConfig.find_by_domain_id(@domain.identifier).enabled?,
  Onetime::CustomDomain::SignupConfig.find_by_domain_id(@domain.identifier).enabled?,
  Onetime::CustomDomain::IncomingConfig.find_by_domain_id(@domain.identifier).enabled?,
]
#=> [false, false, false]

## ensure re-run: nothing missing, nothing created, NO audit event
@before_audit = Onetime::ColonelAuditEvent.count
post "/api/colonel/domains/#{@extid}/configs/ensure", { 'dry_run' => 'false' }, colonel_headers
@resp = JSON.parse(last_response.body)
[@resp['details']['created'], @resp['details']['existing'].sort, Onetime::ColonelAuditEvent.count - @before_audit]
#=> [[], %w[api homepage incoming signin signup], 0]

# ----------------------------------------------------------------
# PUT — upsert signin (update path after ensure)
# ----------------------------------------------------------------

## PUT signin: partial update returns real JSON booleans and outcome=updated
@before_audit = Onetime::ColonelAuditEvent.count
put "/api/colonel/domains/#{@extid}/configs/signin",
  { 'enabled' => 'true', 'signin_enabled' => 'true' }, confirming_config(@domain, 'signin')
@resp = JSON.parse(last_response.body)
d = @resp['details']
[last_response.status, d['kind'], d['outcome'],
 d['config']['enabled'], d['config']['signin_enabled'],
 d['config']['email_auth_enabled'], d['config']['restrict_to']]
#=> [200, 'signin', 'updated', true, true, false, nil]

## PUT signin: ONE domain.config_upsert audit event with changed field NAMES
@after_audit = Onetime::ColonelAuditEvent.count
@latest = Onetime::ColonelAuditEvent.recent(1, 0).first
[@after_audit - @before_audit, @latest['verb'], @latest['actor'],
 @latest['detail'].to_s.include?('signin_enabled')]
#=> [1, "domain.config_upsert", @colonel.extid, true]

## PUT signin: the stored record really flipped (real booleans in the model)
cfg = Onetime::CustomDomain::SigninConfig.find_by_domain_id(@domain.identifier)
[cfg.enabled?, cfg.signin_enabled?, cfg.email_auth_enabled?]
#=> [true, true, false]

## PUT signin on the SECOND domain (no ensure ran there): outcome=created
@before_audit = Onetime::ColonelAuditEvent.count
put "/api/colonel/domains/#{@extid2}/configs/signin", { 'enabled' => 'true' }, confirming_config(@domain2, 'signin')
@resp = JSON.parse(last_response.body)
[last_response.status, @resp['details']['outcome'], @resp['details']['config']['enabled'],
 Onetime::ColonelAuditEvent.count - @before_audit]
#=> [200, 'created', true, 1]

# ----------------------------------------------------------------
# PUT — validation failures (4xx)
#
# The two rejections below fail at DIFFERENT layers, and the audit trail
# reflects exactly that. The enum is rejected by the ADAPTER's coerce_field!
# before the op is ever constructed, so nothing was attempted against the
# domain and nothing is recorded. The allowlist is rejected by the MODEL
# SETTER inside the op's apply_update, i.e. mid-mutation and after the write
# path was entered — Onetime::AuditedFailure records one result: :failure
# event and re-raises, and the 422 is unchanged.
# ----------------------------------------------------------------

## PUT signin with an invalid restrict_to enum -> 422 at the adapter, no audit
@before_audit = Onetime::ColonelAuditEvent.count
put "/api/colonel/domains/#{@extid}/configs/signin", { 'restrict_to' => 'bogus' }, confirming_config(@domain, 'signin')
[last_response.status, Onetime::ColonelAuditEvent.count - @before_audit]
#=> [422, 0]

## PUT signup with an invalid allowed_signup_domains entry -> 422 from the model setter
@before_audit = Onetime::ColonelAuditEvent.count
put "/api/colonel/domains/#{@extid}/configs/signup",
  { 'allowed_signup_domains' => ['not_a_domain'] }, confirming_config(@domain, 'signup')
[last_response.status, Onetime::ColonelAuditEvent.count - @before_audit]
#=> [422, 1]

## the in-op failure is recorded with the UNCHANGED upsert verb + domain target
@latest = Onetime::ColonelAuditEvent.recent(1, 0).first
[@latest['verb'], @latest['target'], @latest['result'],
 @latest['detail']['config'], @latest['detail']['changed']]
#=> ["domain.config_upsert", @extid, "failure", 'signup', ['allowed_signup_domains']]

## PUT signup with a VALID allowlist round-trips the array
put "/api/colonel/domains/#{@extid}/configs/signup",
  { 'validation_strategy' => 'domain_allowlist', 'allowed_signup_domains' => ['corp.example.com'] }, confirming_config(@domain, 'signup')
@resp = JSON.parse(last_response.body)
[last_response.status, @resp['details']['config']['validation_strategy'], @resp['details']['config']['allowed_signup_domains']]
#=> [200, 'domain_allowlist', ['corp.example.com']]

## PUT sso -> 422: not editable via the colonel API
put "/api/colonel/domains/#{@extid}/configs/sso", { 'enabled' => 'true' }, colonel_headers
[last_response.status, last_response.body.include?('not editable')]
#=> [422, true]

## PUT mailer -> 422: not editable via the colonel API
put "/api/colonel/domains/#{@extid}/configs/mailer", { 'enabled' => 'true' }, colonel_headers
last_response.status
#=> 422

## PUT an unknown kind -> 404
put "/api/colonel/domains/#{@extid}/configs/bogus", { 'enabled' => 'true' }, colonel_headers
last_response.status
#=> 404

## PUT on an unknown domain extid -> 404
put "/api/colonel/domains/cd_nonexistent#{@timestamp}/configs/signin", { 'enabled' => 'true' }, colonel_headers
last_response.status
#=> 404

## GET an unknown domain extid -> 404
get "/api/colonel/domains/cd_nonexistent#{@timestamp}/configs", {}, colonel_headers
last_response.status
#=> 404

# ----------------------------------------------------------------
# Redaction — SsoConfig / MailerConfig credentials never serialize
# ----------------------------------------------------------------

## An SsoConfig with real credentials serializes PRESENCE only — never the value
Onetime::CustomDomain::SsoConfig.create!(
  domain_id: @domain.identifier,
  provider_type: 'oidc',
  client_id: 'test-client-id',
  client_secret: 'test-client-secret-value',
  issuer: 'https://issuer.example.com',
  enabled: 'true',
)
get "/api/colonel/domains/#{@extid}/configs", {}, colonel_headers
@resp = JSON.parse(last_response.body)
sso = @resp['details']['configs']['sso']
[sso['exists'], sso['config']['enabled'], sso['config']['provider_type'],
 sso['config']['has_client_id'], sso['config']['has_client_secret'],
 sso['config']['issuer'], last_response.body.include?('test-client-id'),
 last_response.body.include?('test-client-secret-value')]
#=> [true, true, 'oidc', true, true, 'https://issuer.example.com', false, false]

## A MailerConfig with a real api_key serializes presence only — never the value.
## (MailerConfig.create! sets encrypted fields AFTER save internally; passing
## api_key: here exercises that path.)
Onetime::CustomDomain::MailerConfig.create!(
  domain_id: @domain.identifier,
  from_address: "notify@colonel-dc-#{@timestamp}.example.com",
  api_key: 'test-mailer-api-key-value',
)
get "/api/colonel/domains/#{@extid}/configs", {}, colonel_headers
@resp = JSON.parse(last_response.body)
mailer = @resp['details']['configs']['mailer']
[mailer['exists'], mailer['config']['from_address'], mailer['config']['has_api_key'],
 last_response.body.include?('test-mailer-api-key-value'),
 last_response.body.include?('test-client-secret-value')]
#=> [true, "notify@colonel-dc-#{@timestamp}.example.com", true, false, false]

# ----------------------------------------------------------------
# DELETE
# ----------------------------------------------------------------

## DELETE signin: 200 with deleted:true and ONE domain.config_delete audit event
@before_audit = Onetime::ColonelAuditEvent.count
delete "/api/colonel/domains/#{@extid}/configs/signin", {}, confirming_config(@domain, 'signin')
@resp = JSON.parse(last_response.body)
@latest = Onetime::ColonelAuditEvent.recent(1, 0).first
[last_response.status, @resp['details']['kind'], @resp['details']['deleted'],
 Onetime::ColonelAuditEvent.count - @before_audit, @latest['verb'], @latest['actor']]
#=> [200, 'signin', true, 1, "domain.config_delete", @colonel.extid]

## DELETE signin again: the record is gone -> 404 and ONE result: :failure event
@before_audit = Onetime::ColonelAuditEvent.count
delete "/api/colonel/domains/#{@extid}/configs/signin", {}, confirming_config(@domain, 'signin')
[last_response.status, Onetime::ColonelAuditEvent.count - @before_audit,
 Onetime::CustomDomain::SigninConfig.exists_for_domain?(@domain.identifier)]
#=> [404, 1, false]

## the refused delete carries the UNCHANGED verb + domain target, result failure
@latest = Onetime::ColonelAuditEvent.recent(1, 0).first
[@latest['verb'], @latest['target'], @latest['result'],
 @latest['detail']['reason'], @latest['detail']['config']]
#=> ["domain.config_delete", @extid, "failure", 'not_found', 'signin']

## DELETE sso: the credential kinds are deletable (recovery posture)
delete "/api/colonel/domains/#{@extid}/configs/sso", {}, confirming_config(@domain, 'sso')
@resp = JSON.parse(last_response.body)
[last_response.status, @resp['details']['deleted'],
 Onetime::CustomDomain::SsoConfig.exists_for_domain?(@domain.identifier)]
#=> [200, true, false]

## DELETE an unknown kind -> 404
delete "/api/colonel/domains/#{@extid}/configs/bogus", {}, colonel_headers
last_response.status
#=> 404

# ----------------------------------------------------------------
# Teardown
# ----------------------------------------------------------------
Onetime::CustomDomain::ConfigRegistry.slugs.each do |slug|
  Onetime::CustomDomain::ConfigRegistry.model_for(slug).delete_for_domain!(@domain.identifier)  rescue nil
  Onetime::CustomDomain::ConfigRegistry.model_for(slug).delete_for_domain!(@domain2.identifier) rescue nil
end
@domain.destroy!    rescue nil
@domain2.destroy!   rescue nil
@org.destroy!       rescue nil
@org_owner.destroy! rescue nil
@colonel.destroy!   rescue nil
@regular.destroy!   rescue nil

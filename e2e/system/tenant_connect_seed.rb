# frozen_string_literal: true

# Fixture seed for the Playwright tenant Connect acceptance project
# (e2e/system/connected-identities-custom-host.spec.ts).
#
# Run it from the repository root with the SAME environment as the armed
# server process (RACK_ENV=test, AUTHENTICATION_MODE=full, AUTH_DATABASE_URL,
# REDIS_URL, DOMAINS_ENABLED=true, ORGS_SSO_ENABLED=true and the secrets), so
# both sides write and read one datastore and one authdb:
#
#   bundle exec ruby e2e/system/tenant_connect_seed.rb
#
# It seeds, idempotently, exactly what e2e/system/README.md lists:
#
#   - one organization with an owner Customer;
#   - one custom domain (the E2E_TENANT_CONNECT_ORIGIN host) in that
#     organization, with an enabled OIDC SsoConfig whose issuer is
#     E2E_TENANT_CONNECT_ISSUER and a SigninConfig that enables password
#     sign-in AND SSO on the domain;
#   - two open (Verified) accounts with an Argon2 password hash, paired
#     Customers, and active exact-domain memberships in the organization;
#   - NO identity on either account, and NO identity anywhere for the
#     (provider, uid) tuple the boot shim asserts.
#
# The records mirror what apps/web/auth/spec/support/oauth_flow_helper.rb
# (setup_oauth_test_domain) and account_seed_helper.rb build for the
# equivalent request specs, so the browser journey runs against the same
# shapes the RSpec matrix already covers.
#
# Same arming contract as tenant_connect_test_boot.rb: refuses to run unless
# the process is explicitly a tenant Connect test process. The authdb is
# migrated here because the RodauthMigrations boot initializer skips under
# RACK_ENV=test, so nothing else creates the schema in this lane.

unless ENV['RACK_ENV'] == 'test' && ENV['E2E_TENANT_CONNECT_ARMED'] == '1'
  abort 'tenant Connect E2E seed requires RACK_ENV=test and E2E_TENANT_CONNECT_ARMED=1'
end

require 'uri'

base_path             = File.expand_path('../..', __dir__)
$LOAD_PATH.unshift File.join(base_path, 'lib')
$LOAD_PATH.unshift File.join(base_path, 'apps', 'api')
$LOAD_PATH.unshift File.join(base_path, 'apps', 'web')
ENV['ONETIME_HOME'] ||= base_path

require 'onetime' # loads bundler/setup
require 'onetime/models'
require 'argon2'
require 'auth/database'
require 'auth/migrator'

def required_env(name)
  value = ENV.fetch(name, '').strip
  abort "tenant Connect E2E seed: #{name} is required" if value.empty?
  value
end

ORIGIN          = required_env('E2E_TENANT_CONNECT_ORIGIN')
TENANT_HOST     = URI.parse(ORIGIN).host.to_s.downcase
PROVIDER        = ENV.fetch('E2E_TENANT_CONNECT_PROVIDER', 'oidc')
UID             = required_env('E2E_TENANT_CONNECT_UID')
ISSUER          = required_env('E2E_TENANT_CONNECT_ISSUER')
PASSWORD        = required_env('E2E_TENANT_CONNECT_PASSWORD')
OWNER_EMAIL     = required_env('E2E_TENANT_CONNECT_OWNER_EMAIL')
SECOND_EMAIL    = required_env('E2E_TENANT_CONNECT_SECOND_EMAIL')
ORG_OWNER       = ENV.fetch('E2E_TENANT_CONNECT_ORG_OWNER_EMAIL', 'tenant-org-owner@example.test')
ORG_NAME        = 'Tenant Connect E2E'
STATUS_VERIFIED = 2 # account_statuses: Verified (open account, no verify-account branch)

abort "tenant Connect E2E seed: could not parse a host from E2E_TENANT_CONNECT_ORIGIN=#{ORIGIN.inspect}" if TENANT_HOST.empty?
abort "tenant Connect E2E seed: only the oidc provider is seeded (got #{PROVIDER.inspect})" unless PROVIDER == 'oidc'

Onetime.boot! :cli

abort 'tenant Connect E2E seed: AUTHENTICATION_MODE=full is required' unless Onetime.auth_config.full_enabled?
abort 'tenant Connect E2E seed: DOMAINS_ENABLED=true is required' unless OT.conf.dig('features', 'domains', 'enabled')
abort 'tenant Connect E2E seed: ORGS_SSO_ENABLED=true is required' unless OT.conf.dig('features', 'organizations', 'sso_enabled')

Auth::Migrator.run_if_needed
db = Auth::Database.connection
abort 'tenant Connect E2E seed: auth database unavailable' unless Auth::Database.available?

def ensure_customer(email)
  normalized = OT::Utils.normalize_email(email)
  Onetime::Customer.find_by_email(normalized) || Onetime::Customer.create!(email: normalized)
end

# --- Organization + custom domain ------------------------------------------
org_owner = ensure_customer(ORG_OWNER)
org       = org_owner.organization_instances.find { |candidate| candidate.display_name == ORG_NAME } ||
            Onetime::Organization.create!(ORG_NAME, org_owner, org_owner.email)

domain   = Onetime::CustomDomain.load_by_display_domain(TENANT_HOST)
if domain && domain.org_id.to_s != org.objid.to_s
  abort "tenant Connect E2E seed: #{TENANT_HOST} already belongs to another organization (#{domain.org_id})"
end
domain ||= Onetime::CustomDomain.create!(TENANT_HOST, org.objid)

# Recreate the credentials store every run so the issuer always matches the
# E2E_TENANT_CONNECT_ISSUER the boot shim asserts in the mock auth hash.
Onetime::CustomDomain::SsoConfig.delete_for_domain!(domain.identifier) if Onetime::CustomDomain::SsoConfig.exists_for_domain?(domain.identifier)
Onetime::CustomDomain::SsoConfig.create!(
  domain_id: domain.identifier,
  provider_type: 'oidc',
  display_name: 'Tenant Connect E2E IdP',
  issuer: ISSUER,
  client_id: 'tenant-connect-e2e-client',
  client_secret: 'tenant-connect-e2e-secret',
  enabled: true,
)

signin_config = Onetime::CustomDomain::SigninConfig.find_by_domain_id(domain.identifier)
if signin_config
  signin_config.enabled        = true
  signin_config.signin_enabled = true
  signin_config.sso_enabled    = true
  signin_config.updated        = Familia.now.to_i
  signin_config.save
else
  Onetime::CustomDomain::SigninConfig.create!(
    domain_id: domain.identifier, enabled: true, signin_enabled: true, sso_enabled: true,
  )
end

# --- Accounts ----------------------------------------------------------------
# Argon2 parameters mirror apps/web/auth/config/features/argon2.rb under
# RACK_ENV=test; the pepper is the one the server verifies with.
hasher_options          = { t_cost: 1, m_cost: 5, p_cost: 1 }
hasher_options[:secret] = Onetime.auth_config.argon2_secret if Onetime.auth_config.argon2_secret
hasher                  = Argon2::Password.new(**hasher_options)

# The tuple must be unclaimed before the first journey binds it.
db[:account_identities].where(provider: PROVIDER, uid: UID).delete

[OWNER_EMAIL, SECOND_EMAIL].each do |email|
  normalized = OT::Utils.normalize_email(email)
  customer   = ensure_customer(normalized)

  account_id = db[:accounts].where(email: normalized).get(:id)
  if account_id
    db[:accounts].where(id: account_id).update(status_id: STATUS_VERIFIED, external_id: customer.extid)
  else
    account_id = db[:accounts].insert(email: normalized, status_id: STATUS_VERIFIED, external_id: customer.extid)
  end

  password_hash = hasher.create(PASSWORD)
  if db[:account_password_hashes].where(id: account_id).empty?
    db[:account_password_hashes].insert(id: account_id, password_hash: password_hash)
  else
    db[:account_password_hashes].where(id: account_id).update(password_hash: password_hash)
  end

  db[:account_identities].where(account_id: account_id).delete

  Onetime::OrganizationMembership.ensure_membership(
    org, customer, role: 'member', domain_scope_id: domain.objid, provisioning_source: 'sso'
  )

  puts "seeded account #{normalized} (account_id=#{account_id}, extid=#{customer.extid})"
end

puts "seeded tenant #{TENANT_HOST} (domain_id=#{domain.identifier}, org=#{org.objid}, issuer=#{ISSUER})"

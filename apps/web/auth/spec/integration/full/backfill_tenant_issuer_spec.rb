# apps/web/auth/spec/integration/full/backfill_tenant_issuer_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# Issue: #3840 Phase 1 / #3838 item 5 — operator-run backfill of the tenant
# `issuer` onto legacy sentinel-issuer ('') SSO identity rows.
#
# Drives the SHIPPED operation Auth::Operations::BackfillTenantIssuer against
# the REAL migrated account_identities schema (migration 008 runs during boot)
# AND real Valkey Customer/Organization/CustomDomain/SsoConfig/OrganizationMembership
# fixtures. Companion to omniauth_issuer_scoped_identity_spec.rb: that file proves
# the READ path (lookup_identity); this file proves the WRITE path (the
# remediation) and that a stamped row is actually USABLE by the tenant read path.
#
# The hardened operation passes TWO fail-closed gates before any write:
#   GATE 1 (domain scope): the account's active OrganizationMembership must be
#     permitted to access THIS domain (can_access_domain? — org-scoped OR
#     domain_scope_id == domain.objid). A plain member? check is NOT enough:
#     one org can host many domains, each with its own issuer.
#   GATE 2 (provenance): customer.signup_domain_id must equal domain.identifier.
#     Org membership alone can't tell a tenant-IdP-minted '' row from a
#     platform-IdP-minted one; a blank/mismatched signup_domain_id fails closed
#     to :skipped_ambiguous_origin so an operator can review manually.
#
# NOTE ON IDENTIFIERS: CustomDomain#identifier == #domainid == #objid (aliased),
# a RANDOM Familia ObjectIdentifier — never name-derived. Fixtures read it off
# the loaded record; signup_domain_id is set to domain.identifier to model a
# genuine tenant signup, and memberships are domain-scoped to domain.objid.
#
# WHY BOTH BACKENDS (SQLite + Postgres): the dedupe / conflict / race paths turn
# on the composite unique index (provider, issuer, uid) and on UPDATE-rowcount
# semantics, which differ between engines. Running both is the regression guard.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTHENTICATION_MODE=full, ORGS_SSO_ENABLED=true
#
# RUN (SQLite lane):
#   RACK_ENV=test AUTHENTICATION_MODE=full AUTH_DATABASE_URL=sqlite::memory: \
#     ORGS_SSO_ENABLED=true LANG=en_US.UTF-8 \
#     bundle exec rspec apps/web/auth/spec/integration/full/backfill_tenant_issuer_spec.rb \
#     --tag '~postgres_database'
#
# RUN (Postgres lane):
#   RACK_ENV=test AUTHENTICATION_MODE=full \
#     AUTH_DATABASE_URL='postgresql://onetime_user:testpass@localhost:5432/onetime_auth_test' \
#     AUTH_DATABASE_URL_MIGRATIONS='postgresql://onetime_migrator:migratepass@localhost:5432/onetime_auth_test' \
#     ORGS_SSO_ENABLED=true LANG=en_US.UTF-8 \
#     bundle exec rspec apps/web/auth/spec/integration/full/backfill_tenant_issuer_spec.rb
# =============================================================================

require_relative '../../spec_helper'
require 'stringio'

RSpec.describe 'Tenant issuer backfill operation (#3840 Phase 1)', type: :integration do
  before(:all) do
    require 'onetime' unless defined?(Onetime)
    Onetime.boot! :test unless Onetime.ready?
    # The operation is lazily require_relative'd by the CLI, not autoloaded.
    # Its `include Onetime::LoggerMethods` needs the app booted, so require it
    # here (post-boot) rather than at file top.
    require_relative '../../../operations/backfill_tenant_issuer'
    require_relative '../../../operations/join_domain_organization'
    # Load the Dry::CLI command tree (bin/ots) for the in-process CLI smoke.
    require 'onetime/cli'
  end

  let(:feature) { Auth::Config::Features::OmniAuth }
  let(:db) { Auth::Database.connection }
  let(:ds) { db[:account_identities] }
  let(:cols) { { id_col: :id, provider_col: :provider, uid_col: :uid, issuer_col: :issuer } }

  # A resolvable, non-sentinel OIDC issuer to stamp (unnormalized — must
  # byte-match sso_config.issuer, mirroring resolve_issuer).
  let(:tenant_issuer) { 'https://tenant-idp.example.com/' }

  # Track auth-DB rows for explicit cleanup (belt-and-suspenders; the harness's
  # clear_auth_database also wipes them). Familia fixtures are flushed per-example.
  let(:created_account_ids) { [] }
  let(:created_identity_ids) { [] }

  after do
    created_identity_ids.each { |id| ds.where(id: id).delete }
    created_account_ids.each { |id| db[:accounts].where(id: id).delete }
  end

  # ==========================================================================
  # Fixture helpers
  # ==========================================================================

  Tenant = Struct.new(:domain, :org, :sso, :provider, :issuer, keyword_init: true)

  def unique_email(prefix)
    "#{prefix}-#{SecureRandom.hex(6)}@backfill-tenant-test.example.com"
  end

  def build_org
    run = SecureRandom.hex(6)
    owner = Onetime::Customer.new(email: "owner-#{run}@backfill-tenant-test.example.com")
    owner.save
    Onetime::Organization.create!("Backfill Org #{run}", owner, "contact-#{run}@backfill-tenant-test.example.com")
  end

  # Create a CustomDomain + SsoConfig on an existing org.
  def build_domain_on(org, provider_type: 'oidc', issuer: :default, tenant_id: nil, grant_org_scope: false, enabled: true)
    issuer = (provider_type == 'oidc' ? tenant_issuer : nil) if issuer == :default
    run = SecureRandom.hex(6)

    display = "secrets-#{run}.backfill-tenant-test.example.com"
    domain = Onetime::CustomDomain.new(display_domain: display, org_id: org.org_id)
    domain.save
    Onetime::CustomDomain.display_domain_index.put(display, domain.domainid)

    attrs = {
      domain_id: domain.identifier,
      provider_type: provider_type,
      display_name: "Backfill SSO #{run}",
      client_id: "client-#{run}",
      client_secret: "secret-#{run}",
      enabled: enabled,
      grant_org_scope: grant_org_scope,
    }
    attrs[:issuer]    = issuer    unless issuer.nil?
    attrs[:tenant_id] = tenant_id unless tenant_id.nil?
    sso = Onetime::CustomDomain::SsoConfig.create!(**attrs)

    Tenant.new(domain: domain, org: org, sso: sso, provider: sso.platform_route_name, issuer: issuer)
  end

  def build_tenant(**kwargs)
    build_domain_on(build_org, **kwargs)
  end

  # Create a Customer, give them a real OrganizationMembership, and set their
  # signup provenance.
  #
  # @param membership :domain_scoped (JoinDomainOrganization → active membership
  #   with domain_scope_id = domain.objid, the production tenant-SSO path),
  #   :org_scoped (active, domain_scope_id nil), :scoped_to (active, scoped to the
  #   passed domain_scope_id), or :none.
  # @param signup :match (signup_domain_id = domain.identifier), :blank (unset),
  #   or a String (some other identifier).
  def create_member(tenant, membership: :domain_scoped, signup: :match, domain_scope_id: nil)
    cust = Onetime::Customer.new(email: unique_email('member'))
    cust.save

    case membership
    when :domain_scoped
      Auth::Operations::JoinDomainOrganization.new(customer: cust, domain_id: tenant.domain.identifier).call
      m = Onetime::OrganizationMembership.find_by_org_customer(tenant.org.objid, cust.objid)
      unless m&.active? && m.can_access_domain?(tenant.domain)
        raise "fixture: expected active domain-scoped membership, got #{m.inspect}"
      end
    when :org_scoped
      Onetime::OrganizationMembership.ensure_membership(tenant.org, cust, role: 'member', domain_scope_id: nil, provisioning_source: 'sso')
    when :scoped_to
      Onetime::OrganizationMembership.ensure_membership(tenant.org, cust, role: 'member', domain_scope_id: domain_scope_id, provisioning_source: 'sso')
    when :none
      # no membership
    end

    sdi = case signup
          when :match then tenant.domain.identifier
          when :blank then nil
          else signup
          end
    unless sdi.nil?
      cust.signup_domain_id = sdi
      cust.save
    end
    cust
  end

  def insert_account(customer)
    id = db[:accounts].insert(email: customer.email, status_id: 1, external_id: customer.extid)
    created_account_ids << id
    id
  end

  def insert_identity(account_id:, tenant:, issuer:, uid: nil, provider: nil)
    uid ||= "sub-#{SecureRandom.hex(8)}"
    provider ||= tenant.provider
    id = ds.insert(account_id: account_id, provider: provider, issuer: issuer, uid: uid)
    created_identity_ids << id
    { identity_id: id, uid: uid, account_id: account_id }
  end

  # An in-scope, right-provenance member with a legacy '' identity row — the row
  # the operation SHOULD stamp. Passes both gates.
  def seed_stampable(tenant, uid: nil, issuer: '', membership: :domain_scoped)
    cust = create_member(tenant, membership: membership, signup: :match)
    account_id = insert_account(cust)
    row = insert_identity(account_id: account_id, tenant: tenant, issuer: issuer, uid: uid)
    row.merge(customer: cust, account_id: account_id)
  end

  # An accounts row with NO external_id (no resolvable Customer) + a legacy '' row.
  def seed_orphan_identity(tenant, uid: nil)
    account_id = db[:accounts].insert(email: unique_email('orphan'), status_id: 1)
    created_account_ids << account_id
    insert_identity(account_id: account_id, tenant: tenant, issuer: '', uid: uid).merge(account_id: account_id)
  end

  def new_operation(tenant, issuer: nil, dry_run: true)
    Auth::Operations::BackfillTenantIssuer.new(domain: tenant.domain, issuer: issuer, dry_run: dry_run)
  end

  def issuer_of(identity_id)
    ds.where(id: identity_id).get(:issuer)
  end

  # ==========================================================================
  # 1. Stamp happy path (both gates satisfied) + correctness rail
  # ==========================================================================

  describe 'stamp happy path (in-scope, right provenance)' do
    it 'reports :would_stamp and writes nothing in dry-run' do
      tenant = build_tenant
      row    = seed_stampable(tenant)

      results = new_operation(tenant, dry_run: true).call

      expect(results.map(&:status)).to eq([:would_stamp])
      expect(results.first.issuer).to eq(tenant_issuer)
      expect(results.first.customer_extid).to eq(row[:customer].extid)
      expect(issuer_of(row[:identity_id])).to eq('')
    end

    it 'stamps the resolved issuer onto the legacy row in a live run' do
      tenant = build_tenant
      row    = seed_stampable(tenant)

      results = new_operation(tenant, dry_run: false).call

      expect(results.map(&:status)).to eq([:stamped])
      expect(issuer_of(row[:identity_id])).to eq(tenant_issuer)
    end

    # CORRECTNESS RAIL: prove the stamped row is usable by the real tenant read
    # path (the whole point). Tenant lookup misses before, matches after.
    it 'makes the row resolvable by the real tenant lookup_identity (issuer-exact)' do
      tenant = build_tenant
      row    = seed_stampable(tenant)
      uid    = row[:uid]

      before = feature.lookup_identity(ds: ds, **cols, provider: tenant.provider, uid: uid,
                                                       resolved_issuer: tenant_issuer, platform_path: false)
      expect(before).to be_nil

      new_operation(tenant, dry_run: false).call

      after = feature.lookup_identity(ds: ds, **cols, provider: tenant.provider, uid: uid,
                                                      resolved_issuer: tenant_issuer, platform_path: false)
      expect(after).not_to be_nil
      expect(after[:account_id]).to eq(row[:account_id])
      expect(after[:issuer]).to eq(tenant_issuer)
    end
  end

  # ==========================================================================
  # 2. GATE 1 — domain scope
  # ==========================================================================

  describe 'GATE 1: domain scope' do
    # Scenario (a): org hosts Domain A and Domain B. A member scoped to A is
    # out-of-scope when backfilling B, even though they're an active org member.
    it 'excludes a member scoped to a DIFFERENT domain in the same org (multi-domain org)' do
      org      = build_org
      domain_a = build_domain_on(org, issuer: 'https://idp-a.example.com/')
      domain_b = build_domain_on(org, issuer: 'https://idp-b.example.com/')

      # Member domain-scoped to A, correct provenance for A. Their '' row shares
      # provider 'oidc' so it is a candidate for B's run too.
      cust = create_member(domain_a, membership: :scoped_to, signup: domain_a.domain.identifier,
                                     domain_scope_id: domain_a.domain.objid)
      account_id = insert_account(cust)
      row = insert_identity(account_id: account_id, tenant: domain_b, issuer: '')

      results = new_operation(domain_b, dry_run: false).call

      expect(results.map(&:status)).to eq([:skipped_out_of_scope])
      expect(issuer_of(row[:identity_id])).to eq('')
    end

    it 'excludes an account with no active membership' do
      tenant = build_tenant
      cust   = create_member(tenant, membership: :none, signup: :match)
      account_id = insert_account(cust)
      row = insert_identity(account_id: account_id, tenant: tenant, issuer: '')

      results = new_operation(tenant, dry_run: false).call

      expect(results.map(&:status)).to eq([:skipped_out_of_scope])
      expect(issuer_of(row[:identity_id])).to eq('')
    end

    # Scenario (d): an org-scoped member (domain_scope_id nil) passes Gate 1 via
    # org_scoped?, then is disambiguated by Gate 2 (provenance matches) → stamp.
    it 'admits an org-scoped member (org_scoped? satisfies the gate) and stamps' do
      tenant = build_tenant
      row    = seed_stampable(tenant, membership: :org_scoped)

      results = new_operation(tenant, dry_run: false).call

      expect(results.map(&:status)).to eq([:stamped])
      expect(issuer_of(row[:identity_id])).to eq(tenant_issuer)
    end
  end

  # ==========================================================================
  # 3. GATE 2 — provenance (formerly the FLAGGED platform/tenant ambiguity)
  # ==========================================================================
  #
  # The pre-hardening spec DOCUMENTED HARM here: an in-org member's platform-
  # minted '' row was stamped, breaking their platform self-heal. Gate 2 removes
  # that harm — a row whose signup_domain_id doesn't match this domain is left
  # untouched, and its platform '' self-heal STILL works.

  describe 'GATE 2: provenance' do
    let(:platform_issuer) { 'https://platform-idp.example.com' }

    it 'skips a member with a BLANK signup_domain_id and preserves platform self-heal' do
      tenant = build_tenant
      # In-scope (domain-scoped active membership) but provenance is blank: the
      # '' row may be platform-minted, so it must NOT be stamped.
      cust = create_member(tenant, membership: :domain_scoped, signup: :blank)
      account_id = insert_account(cust)
      row = insert_identity(account_id: account_id, tenant: tenant, issuer: '')

      results = new_operation(tenant, dry_run: false).call
      expect(results.map(&:status)).to eq([:skipped_ambiguous_origin])

      # Row untouched...
      expect(issuer_of(row[:identity_id])).to eq('')

      # ...and the platform self-heal path STILL matches the '' row (harm gone):
      # a PLATFORM callback resolving a real issuer finds the legacy row and
      # upgrades it — the user's login is NOT broken.
      healed = feature.lookup_identity(ds: ds, **cols, provider: tenant.provider, uid: row[:uid],
                                                       resolved_issuer: platform_issuer, platform_path: true)
      expect(healed).not_to be_nil
      expect(healed[:account_id]).to eq(account_id)
      expect(healed[:issuer]).to eq(platform_issuer)
    end

    it 'skips a member whose signup_domain_id points to ANOTHER domain' do
      tenant = build_tenant
      cust = create_member(tenant, membership: :domain_scoped, signup: 'some-other-domain-identifier')
      account_id = insert_account(cust)
      row = insert_identity(account_id: account_id, tenant: tenant, issuer: '')

      results = new_operation(tenant, dry_run: false).call

      expect(results.map(&:status)).to eq([:skipped_ambiguous_origin])
      expect(issuer_of(row[:identity_id])).to eq('')
    end
  end

  # ==========================================================================
  # 4. Dedupe — same account already carries the exact row (gates satisfied)
  # ==========================================================================

  describe 'dedupe (same account has exact + legacy rows)' do
    it 'drops the stale legacy row and keeps the exact one (live)' do
      tenant = build_tenant
      cust   = create_member(tenant, membership: :domain_scoped, signup: :match)
      account_id = insert_account(cust)
      exact = insert_identity(account_id: account_id, tenant: tenant, issuer: tenant_issuer, uid: 'shared-uid')
      legacy = insert_identity(account_id: account_id, tenant: tenant, issuer: '', uid: 'shared-uid')

      results = new_operation(tenant, dry_run: false).call

      expect(results.map(&:status)).to eq([:deduped])
      expect(ds.where(id: legacy[:identity_id]).count).to eq(0)
      expect(ds.where(id: exact[:identity_id]).get(:issuer)).to eq(tenant_issuer)
    end

    it 'reports :would_dedupe and writes nothing in dry-run' do
      tenant = build_tenant
      cust   = create_member(tenant, membership: :domain_scoped, signup: :match)
      account_id = insert_account(cust)
      exact = insert_identity(account_id: account_id, tenant: tenant, issuer: tenant_issuer, uid: 'shared-uid')
      legacy = insert_identity(account_id: account_id, tenant: tenant, issuer: '', uid: 'shared-uid')

      results = new_operation(tenant, dry_run: true).call

      expect(results.map(&:status)).to eq([:would_dedupe])
      expect(ds.where(id: legacy[:identity_id]).count).to eq(1)
      expect(issuer_of(legacy[:identity_id])).to eq('')
    end
  end

  # ==========================================================================
  # 5. Cross-account conflict — exact row belongs to a DIFFERENT account
  # ==========================================================================

  describe 'cross-account conflict' do
    it 'refuses (:error), never stamping or dropping the legacy row' do
      tenant = build_tenant
      # In-scope account A owns the legacy '' row (passes both gates).
      cust_a  = create_member(tenant, membership: :domain_scoped, signup: :match)
      account_a = insert_account(cust_a)
      legacy  = insert_identity(account_id: account_a, tenant: tenant, issuer: '', uid: 'collide-uid')
      # Account B (a JIT re-mint) already owns the exact (provider, issuer, uid) row.
      account_b = db[:accounts].insert(email: unique_email('other'), status_id: 1)
      created_account_ids << account_b
      other = insert_identity(account_id: account_b, tenant: tenant, issuer: tenant_issuer, uid: 'collide-uid')

      results = new_operation(tenant, dry_run: false).call

      conflict = results.find { |r| r.account_id == account_a }
      expect(conflict.status).to eq(:error)
      expect(conflict.message).to match(/different account/i)
      expect(issuer_of(legacy[:identity_id])).to eq('')
      expect(ds.where(id: other[:identity_id]).get(:issuer)).to eq(tenant_issuer)
    end
  end

  # ==========================================================================
  # 6. No customer — orphan account (no external_id / Customer)
  # ==========================================================================

  describe 'no customer' do
    it 'skips an orphan identity row (:skipped_no_customer)' do
      tenant = build_tenant
      row    = seed_orphan_identity(tenant)

      results = new_operation(tenant, dry_run: false).call

      expect(results.map(&:status)).to eq([:skipped_no_customer])
      expect(issuer_of(row[:identity_id])).to eq('')
    end
  end

  # ==========================================================================
  # 7. Race guard — a live stamp that affects 0 rows yields :error, not :stamped
  # ==========================================================================

  describe 'scan-to-write race guard' do
    it 'returns :error when the stamp UPDATE matches zero rows' do
      tenant = build_tenant
      seeded = seed_stampable(tenant)
      op     = new_operation(tenant, dry_run: false)

      # A candidate as it was scanned (issuer ''), but the row changed underneath
      # to a NON-tenant issuer before the write — so the exact lookup misses AND
      # the stamp's WHERE(issuer='') now matches 0 rows.
      candidate = { id: seeded[:identity_id], account_id: seeded[:account_id],
                    uid: seeded[:uid], provider: tenant.provider, issuer: '' }
      ds.where(id: seeded[:identity_id]).update(issuer: 'https://raced.example.com')

      result = op.process_identity(candidate)

      expect(result.status).to eq(:error)
      expect(result.message).to match(/expected 1|concurrent/i)
      # The raced value is left as-is (not clobbered).
      expect(issuer_of(seeded[:identity_id])).to eq('https://raced.example.com')
    end
  end

  # ==========================================================================
  # 8. Idempotency — a second live run does nothing more
  # ==========================================================================

  describe 'idempotency' do
    it 'produces no further stamp/dedupe on a second live call' do
      tenant = build_tenant
      stamp  = seed_stampable(tenant)
      # A second in-scope account with a dedupe pair.
      cust   = create_member(tenant, membership: :domain_scoped, signup: :match)
      account_id = insert_account(cust)
      exact  = insert_identity(account_id: account_id, tenant: tenant, issuer: tenant_issuer, uid: 'dedupe-uid')
      insert_identity(account_id: account_id, tenant: tenant, issuer: '', uid: 'dedupe-uid')

      first  = new_operation(tenant, dry_run: false).call
      expect(first.map(&:status)).to contain_exactly(:stamped, :deduped)

      second = new_operation(tenant, dry_run: false).call
      expect(second).to be_empty
      expect(issuer_of(stamp[:identity_id])).to eq(tenant_issuer)
      expect(ds.where(id: exact[:identity_id]).get(:issuer)).to eq(tenant_issuer)
    end
  end

  # ==========================================================================
  # 9. Dry-run purity (whole-candidate byte check across every branch)
  # ==========================================================================

  describe 'dry-run purity' do
    it 'leaves every candidate row unchanged while reporting the right :would_*/skip statuses' do
      tenant = build_tenant
      stamp  = seed_stampable(tenant)
      # dedupe pair on a gated account
      cust   = create_member(tenant, membership: :domain_scoped, signup: :match)
      account_id = insert_account(cust)
      insert_identity(account_id: account_id, tenant: tenant, issuer: tenant_issuer, uid: 'd-uid')
      legacy = insert_identity(account_id: account_id, tenant: tenant, issuer: '', uid: 'd-uid')
      # ambiguous-origin row (in-scope, blank provenance)
      amb    = create_member(tenant, membership: :domain_scoped, signup: :blank)
      amb_account = insert_account(amb)
      amb_row = insert_identity(account_id: amb_account, tenant: tenant, issuer: '')

      snapshot = ds.where(provider: tenant.provider).order(:id).select_map([:id, :issuer, :account_id])

      results = new_operation(tenant, dry_run: true).call

      expect(results.map(&:status)).to contain_exactly(:would_stamp, :would_dedupe, :skipped_ambiguous_origin)
      expect(ds.where(provider: tenant.provider).order(:id).select_map([:id, :issuer, :account_id])).to eq(snapshot)
      expect(issuer_of(stamp[:identity_id])).to eq('')
      expect(issuer_of(legacy[:identity_id])).to eq('')
      expect(issuer_of(amb_row[:identity_id])).to eq('')
    end
  end

  # ==========================================================================
  # 10. Issuer resolution (must byte-match resolve_issuer) + sso_enabled?
  # ==========================================================================

  describe 'issuer resolution' do
    it 'oidc uses sso_config.issuer verbatim' do
      tenant = build_tenant(provider_type: 'oidc', issuer: 'https://oidc.example.com')
      expect(new_operation(tenant).issuer).to eq('https://oidc.example.com')
    end

    it 'entra_id derives the login.microsoftonline.com issuer from tenant_id' do
      tenant = build_tenant(provider_type: 'entra_id', issuer: nil, tenant_id: 'contoso-uuid')
      op = new_operation(tenant)
      expect(op.issuer).to eq('https://login.microsoftonline.com/contoso-uuid/v2.0')
      expect(op.provider).to eq('entra')
    end

    it 'refuses google/github (they resolve to the sentinel; nothing to backfill)' do
      %w[google github].each do |ptype|
        tenant = build_tenant(provider_type: ptype, issuer: nil)
        expect { new_operation(tenant) }.to raise_error(Onetime::Problem, /sentinel issuer/i)
      end
    end

    it 'raises when the oidc issuer is blank and no override is given' do
      tenant = build_tenant(provider_type: 'oidc', issuer: '')
      expect { new_operation(tenant) }.to raise_error(Onetime::Problem, /issuer/i)
    end

    it 'raises for entra_id with no tenant_id and no override' do
      tenant = build_tenant(provider_type: 'entra_id', issuer: nil, tenant_id: nil)
      expect { new_operation(tenant) }.to raise_error(Onetime::Problem, /tenant_id/i)
    end

    it 'lets an operator --issuer override win over config for every provider' do
      override = 'https://operator-supplied.example.com'
      oidc = build_tenant(provider_type: 'oidc', issuer: 'https://config.example.com')
      expect(new_operation(oidc, issuer: override).issuer).to eq(override)
      google = build_tenant(provider_type: 'google', issuer: nil)
      expect(new_operation(google, issuer: override).issuer).to eq(override)
    end

    it 'exposes sso_enabled? and constructs (non-fatally) for a disabled config' do
      expect(new_operation(build_tenant).sso_enabled?).to be true
      disabled = build_tenant(enabled: false)
      op = new_operation(disabled)
      expect(op.sso_enabled?).to be false
    end
  end

  # ==========================================================================
  # 11. Constructor fail-fast
  # ==========================================================================

  describe 'constructor fail-fast' do
    it 'raises when the domain has no primary organization' do
      tenant = build_tenant
      allow(tenant.domain).to receive(:primary_organization).and_return(nil)
      expect { new_operation(tenant) }.to raise_error(Onetime::Problem, /no primary organization/i)
    end

    it 'raises when the domain has no SSO config' do
      tenant = build_tenant
      allow(tenant.domain).to receive(:sso_config).and_return(nil)
      expect { new_operation(tenant) }.to raise_error(Onetime::Problem, /no SSO config/i)
    end

    it 'raises when the provider route name is blank' do
      tenant = build_tenant
      sso = tenant.domain.sso_config
      allow(sso).to receive(:platform_route_name).and_return('')
      allow(tenant.domain).to receive(:sso_config).and_return(sso)
      expect { new_operation(tenant) }.to raise_error(Onetime::Problem, /provider route name/i)
    end
  end

  # ==========================================================================
  # 12. CLI smoke (in-process) — real command wiring against gated fixtures
  # ==========================================================================

  describe 'CLI: bin/ots sso backfill-issuer', :cli do
    def run_command(cmd, **kwargs)
      allow(cmd).to receive(:boot_application!)
      out = StringIO.new
      orig = $stdout
      $stdout = out
      begin
        cmd.call(**kwargs)
      ensure
        $stdout = orig
      end
      out.string
    end

    it 'forces dry-run without --confirm and writes nothing (JSON)' do
      tenant = build_tenant
      row    = seed_stampable(tenant)

      cmd = Onetime::CLI::SsoBackfillIssuerCommand.new
      output = run_command(cmd, domain: tenant.domain.display_domain, confirm: false, json: true)

      payload = JSON.parse(output)
      expect(payload['dry_run']).to be true
      expect(payload['issuer']).to eq(tenant_issuer)
      expect(payload['statistics']['stamp']).to eq(1)
      expect(payload['statistics']).to have_key('skipped_ambiguous_origin')
      expect(payload['results'].first['status']).to eq('would_stamp')
      expect(issuer_of(row[:identity_id])).to eq('')
    end

    it 'executes with --confirm and stamps (JSON)' do
      tenant = build_tenant
      row    = seed_stampable(tenant)

      cmd = Onetime::CLI::SsoBackfillIssuerCommand.new
      output = run_command(cmd, domain: tenant.domain.display_domain, confirm: true, json: true)

      payload = JSON.parse(output)
      expect(payload['dry_run']).to be false
      expect(payload['statistics']['stamp']).to eq(1)
      expect(payload['results'].first['status']).to eq('stamped')
      expect(issuer_of(row[:identity_id])).to eq(tenant_issuer)
    end

    it 'prints the legacy-row count and usage for the group root' do
      tenant = build_tenant
      seed_stampable(tenant)

      cmd = Onetime::CLI::SsoCommand.new
      output = run_command(cmd)

      expect(output).to match(/legacy identity row\(s\) with sentinel issuer/)
      expect(output).to include('bin/ots sso backfill-issuer DOMAIN')
    end
  end
end

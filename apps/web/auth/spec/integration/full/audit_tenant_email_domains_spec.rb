# apps/web/auth/spec/integration/full/audit_tenant_email_domains_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# RISK-2026-10-10-01 (#4734): the login gate refuses NEW tenant SSO accounts
# outside the organization's proven email domains; identities bound before
# the gate keep signing in. Auth::Operations::AuditTenantEmailDomains is the
# operator's view of those bindings and, with unlink, their removal.
#
# Drives the operation against the real account_identities schema and real
# Valkey Customer / Organization / CustomDomain / SsoConfig fixtures, then the
# CLI command in-process. Companion to tenant_sso_verified_email_domain_spec.rb
# (the live gate) and backfill_tenant_issuer_spec.rb (the sibling operation).
# The scan is issuer-exact; the issuer override (--issuer) reads the rows the
# sibling stamped with a value other than the derived one, and a zero-row scan
# says so.
#
# A display_domain is unique install-wide, so every tenant here gets its own
# host; "inside" addresses sit at that host, "outside" ones at a domain no
# organization has added.
#
# A domain proves its email namespace only when its ownership rests on
# evidence (CustomDomain#ownership_proven?). The test install runs
# passthrough, where only a Colonel override counts, so the fixtures accept
# ownership by override unless an example says otherwise.
#
# Run with full-sqlite or full-pg-agnostic.
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../../../../../spec/support/saml/test_idp'
require 'stringio'
require 'shellwords'

RSpec.describe 'Tenant SSO email domain audit (#4734)', type: :integration do
  before(:all) do
    require 'onetime' unless defined?(Onetime)
    Onetime.boot! :test unless Onetime.ready?
    require_relative '../../../operations/audit_tenant_email_domains'
    require 'onetime/cli'
  end

  let(:db) { Auth::Database.connection }
  let(:ds) { db[:account_identities] }
  let(:tenant_issuer) { 'https://tenant-idp.example.com/' }
  # What backfill-issuer --issuer stamped onto the rows: not the derived value.
  let(:stamped_issuer) { 'https://login.microsoftonline.com/contoso-tenant/v2.0' }

  let(:created_account_ids) { [] }
  let(:created_identity_ids) { [] }
  let(:fixtures) { [] }

  before do
    allow(Auth::Logging).to receive(:log_auth_event).and_call_original
  end

  after do
    created_identity_ids.each { |id| ds.where(id: id).delete }
    created_account_ids.each { |id| db[:accounts].where(id: id).delete }
    fixtures.reverse_each do |record|
      record.destroy! if record.respond_to?(:exists?) && record.exists?
    rescue StandardError => ex
      warn "[audit spec] cleanup failed: #{ex.class}: #{ex.message}"
    end
  end

  # A constant assigned in a describe block is top-level, and other specs
  # in this directory assign their own Tenant struct with other members;
  # whichever file loads last in a process wins. Named for this file.
  AuditTenant = Struct.new(:host, :domain, :org, :sso, :provider, :issuer, keyword_init: true)

  def build_tenant(provider_type: 'oidc', idp_entity_id: nil)
    run   = SecureRandom.hex(6)
    owner = Onetime::Customer.new(email: "owner-#{run}@audit-tenant-test.example.com")
    owner.save
    org = Onetime::Organization.create!("Audit Org #{run}", owner, "contact-#{run}@audit-tenant-test.example.com")
    fixtures.push(owner, org)

    host   = "secrets-#{run}.audit-tenant-test.example.com"
    domain = Onetime::CustomDomain.parse(host, org.objid)
    domain.ownership_verified   = true
    domain.verified_by_override = true
    domain.save
    org.add_domain(domain)
    Onetime::CustomDomain.display_domain_index.put(host, domain.domainid)
    fixtures << domain

    attrs = {
      domain_id: domain.identifier, provider_type: provider_type,
      display_name: "Audit SSO #{run}", enabled: true,
    }
    case provider_type
    when 'oidc'
      attrs.merge!(issuer: tenant_issuer, client_id: "client-#{run}", client_secret: "secret-#{run}")
    when 'saml'
      attrs.merge!(
        idp_sso_service_url: "https://login.audit-idp.test/#{run}",
        idp_entity_id: idp_entity_id || "https://audit-idp.test/#{run}",
        idp_cert: SamlSpec::TestIdp.new(entity_id: "https://audit-idp.test/#{run}").cert_pem,
      )
    end
    sso = Onetime::CustomDomain::SsoConfig.create!(**attrs)
    fixtures << sso

    issuer = provider_type == 'saml' ? Onetime::SsoProvider::Saml.tenant_issuer(domain.identifier, attrs[:idp_entity_id]) : tenant_issuer
    AuditTenant.new(host: host, domain: domain, org: org, sso: sso, provider: sso.platform_route_name, issuer: issuer)
  end

  # A second custom domain of the same organization, verified or not, so the
  # proven set can extend beyond the tenant host. A verified one is accepted
  # by Colonel override unless `override: false` is passed; `confirmed: true`
  # records a passing TXT check (verified_confirmed_at).
  def add_org_domain(tenant, display_domain, verified:, override: verified, confirmed: false)
    domain                       = Onetime::CustomDomain.parse(display_domain, tenant.org.objid)
    domain.ownership_verified    = verified
    domain.verified_by_override  = override
    domain.verified_confirmed_at = Time.now.to_i - 3600 if confirmed
    domain.save
    tenant.org.add_domain(domain)
    fixtures << domain
    domain
  end

  # A JIT-shaped account: Customer with signup provenance, SQL accounts row,
  # identity row under the tenant's key.
  def seed_identity(tenant, email, signup: :match, provider: nil, issuer: nil, uid: nil)
    cust = Onetime::Customer.new(email: email)
    sdi  = case signup
           when :match then tenant.domain.identifier
           when :blank then nil
           else signup
           end
    cust.signup_domain_id = sdi unless sdi.nil?
    cust.save
    fixtures << cust

    account_id = db[:accounts].insert(email: email, status_id: 2, external_id: cust.extid)
    created_account_ids << account_id
    uid ||= "sub-#{SecureRandom.hex(8)}"
    identity_id = ds.insert(account_id: account_id, provider: provider || tenant.provider,
                                                    issuer: issuer || tenant.issuer, uid: uid)
    created_identity_ids << identity_id
    { customer: cust, account_id: account_id, identity_id: identity_id, uid: uid }
  end

  def new_operation(tenant, unlink: false, dry_run: true, issuer_override: nil)
    Auth::Operations::AuditTenantEmailDomains.new(
      domain: tenant.domain, unlink: unlink, dry_run: dry_run, issuer_override: issuer_override,
    )
  end

  def identity_exists?(id)
    ds.where(id: id).count == 1
  end

  describe 'classification (oidc)' do
    it 'reports an address at the tenant host as inside and an unproven one as outside' do
      tenant  = build_tenant
      inside  = seed_identity(tenant, "member-#{SecureRandom.hex(4)}@#{tenant.host}")
      outside = seed_identity(tenant, "victim-#{SecureRandom.hex(4)}@unrelated.example.org")

      results = new_operation(tenant).call

      by_account = results.to_h { |r| [r.account_id, r] }
      expect(by_account[inside[:account_id]].status).to eq(:inside)
      expect(by_account[outside[:account_id]].status).to eq(:outside)
      expect(by_account[outside[:account_id]].asserted_domain).to eq('unrelated.example.org')
      expect(by_account[outside[:account_id]].email_obscured).not_to include("victim-")
      expect(results.map(&:issuer).uniq).to eq([tenant_issuer])
      expect(results.map(&:provider).uniq).to eq([tenant.provider])
    end

    it 'counts a second verified domain of the organization, and names below it, but not an unverified one' do
      tenant = build_tenant
      run    = SecureRandom.hex(4)
      add_org_domain(tenant, "acme-#{run}.example.com", verified: true)
      add_org_domain(tenant, "pending-#{run}.example.com", verified: false)
      apex  = seed_identity(tenant, "a@acme-#{run}.example.com")
      below = seed_identity(tenant, "b@mail.acme-#{run}.example.com")
      pend  = seed_identity(tenant, "c@pending-#{run}.example.com")

      statuses = new_operation(tenant).call.to_h { |r| [r.account_id, r.status] }

      expect(statuses[apex[:account_id]]).to eq(:inside)
      expect(statuses[below[:account_id]]).to eq(:inside)
      expect(statuses[pend[:account_id]]).to eq(:outside)
    end

    # Passthrough sets ownership_verified for any name the organization
    # registers, without a DNS lookup (ADR-049: not evidence of ownership).
    it 'reports an address in a domain verified only by passthrough as outside' do
      expect(Onetime::CustomDomain.ownership_proof_required?).to be(false)

      tenant = build_tenant
      run    = SecureRandom.hex(4)
      add_org_domain(tenant, "squat-#{run}.example.com", verified: true, override: false)
      squat = seed_identity(tenant, "a@squat-#{run}.example.com")

      statuses = new_operation(tenant).call.to_h { |r| [r.account_id, r.status] }

      expect(statuses[squat[:account_id]]).to eq(:outside)
    end

    it 'reports an address at the tenant host as outside when only passthrough verified it' do
      expect(Onetime::CustomDomain.ownership_proof_required?).to be(false)

      tenant = build_tenant
      tenant.domain.verified_by_override = false
      tenant.domain.save
      member = seed_identity(tenant, "member-#{SecureRandom.hex(4)}@#{tenant.host}")

      statuses = new_operation(tenant).call.to_h { |r| [r.account_id, r.status] }

      expect(statuses[member[:account_id]]).to eq(:outside)
    end

    it 'ignores rows under another issuer or provider' do
      tenant = build_tenant
      seed_identity(tenant, "x@unrelated.example.org", issuer: 'https://other-idp.example.com/')
      seed_identity(tenant, "y@unrelated.example.org", provider: 'entra')

      expect(new_operation(tenant).call).to be_empty
    end

    # Follow-up (1) on the audit side: the proven set, and with it the
    # organization's domain records, is read once per run, not once per row.
    it 'reads the proven set once per run, not once per row' do
      tenant = build_tenant
      seed_identity(tenant, "member-#{SecureRandom.hex(4)}@#{tenant.host}")
      seed_identity(tenant, "victim-#{SecureRandom.hex(4)}@unrelated.example.org")

      op = new_operation(tenant)
      expect(op.organization).to receive(:proven_email_domains_through).once.and_call_original
      expect(op.organization).to receive(:list_domains).once.and_call_original

      expect(op.call.map(&:status)).to contain_exactly(:inside, :outside)
    end
  end

  describe 'classification (saml)' do
    it 'reads rows under the domain-scoped SAML issuer key' do
      tenant  = build_tenant(provider_type: 'saml')
      inside  = seed_identity(tenant, "member-#{SecureRandom.hex(4)}@#{tenant.host}", uid: "nameid-#{SecureRandom.hex(4)}")
      outside = seed_identity(tenant, "victim-#{SecureRandom.hex(4)}@unrelated.example.org", uid: "nameid-#{SecureRandom.hex(4)}")

      op      = new_operation(tenant)
      results = op.call

      expect(op.provider).to eq('saml')
      expect(op.issuer).to start_with("#{tenant.domain.identifier}|https://audit-idp.test/")
      statuses = results.to_h { |r| [r.account_id, r.status] }
      expect(statuses[inside[:account_id]]).to eq(:inside)
      expect(statuses[outside[:account_id]]).to eq(:outside)
    end
  end

  describe 'issuer override' do
    it 'uses the stripped override in place of the derived issuer, for oidc and saml alike' do
      oidc = build_tenant
      saml = build_tenant(provider_type: 'saml')

      expect(new_operation(oidc, issuer_override: "  #{stamped_issuer}  ").issuer).to eq(stamped_issuer)
      expect(new_operation(saml, issuer_override: stamped_issuer).issuer).to eq(stamped_issuer)
      expect(new_operation(oidc, issuer_override: '   ').issuer).to eq(tenant_issuer)
      expect(new_operation(oidc).issuer).to eq(tenant_issuer)
    end

    it 'scans a row stamped with another issuer only when that issuer is given' do
      tenant  = build_tenant
      inside  = seed_identity(tenant, "member-#{SecureRandom.hex(4)}@#{tenant.host}", issuer: stamped_issuer)
      outside = seed_identity(tenant, "victim-#{SecureRandom.hex(4)}@unrelated.example.org", issuer: stamped_issuer)

      expect(new_operation(tenant).call).to be_empty

      results    = new_operation(tenant, issuer_override: stamped_issuer).call
      by_account = results.to_h { |r| [r.account_id, r] }
      expect(by_account[inside[:account_id]].status).to eq(:inside)
      expect(by_account[outside[:account_id]].status).to eq(:outside)
      expect(results.map(&:issuer).uniq).to eq([stamped_issuer])
    end

    it 'unlinks under the override only a row whose signup_domain_id names this domain, and reads no other issuer' do
      tenant  = build_tenant
      other   = seed_identity(tenant, "q@unrelated.example.org", signup: 'cd_somewhere_else', issuer: stamped_issuer)
      minted  = seed_identity(tenant, "victim-#{SecureRandom.hex(4)}@unrelated.example.org", issuer: stamped_issuer)
      derived = seed_identity(tenant, "victim-#{SecureRandom.hex(4)}@unrelated.example.org")

      results = new_operation(tenant, unlink: true, dry_run: false, issuer_override: stamped_issuer).call

      statuses = results.to_h { |r| [r.account_id, r.status] }
      expect(statuses).to eq(other[:account_id] => :skipped_ambiguous_origin, minted[:account_id] => :unlinked)
      expect(identity_exists?(other[:identity_id])).to be true
      expect(identity_exists?(minted[:identity_id])).to be false
      expect(identity_exists?(derived[:identity_id])).to be true
      expect(Auth::Logging).to have_received(:log_auth_event).with(
        :omniauth_tenant_identity_unlinked,
        hash_including(account_id: minted[:account_id], domain_id: tenant.domain.identifier),
      ).once
    end
  end

  describe 'provenance gate' do
    it 'never unlinks an outside row whose signup_domain_id is blank or names another domain' do
      tenant = build_tenant
      blank  = seed_identity(tenant, "p@unrelated.example.org", signup: :blank)
      other  = seed_identity(tenant, "q@unrelated.example.org", signup: 'cd_somewhere_else')

      results = new_operation(tenant, unlink: true, dry_run: false).call

      expect(results.map(&:status)).to all(eq(:skipped_ambiguous_origin))
      expect(identity_exists?(blank[:identity_id])).to be true
      expect(identity_exists?(other[:identity_id])).to be true
      expect(Auth::Logging).not_to have_received(:log_auth_event).with(:omniauth_tenant_identity_unlinked, anything)
    end
  end

  describe 'unlink' do
    it 'previews in dry run and writes nothing' do
      tenant  = build_tenant
      outside = seed_identity(tenant, "victim-#{SecureRandom.hex(4)}@unrelated.example.org")

      results = new_operation(tenant, unlink: true, dry_run: true).call

      expect(results.map(&:status)).to eq([:would_unlink])
      expect(identity_exists?(outside[:identity_id])).to be true
      expect(Auth::Logging).not_to have_received(:log_auth_event).with(:omniauth_tenant_identity_unlinked, anything)
    end

    it 'deletes exactly the failing row, keeps the account and customer, logs the event, and is idempotent' do
      tenant  = build_tenant
      inside  = seed_identity(tenant, "member-#{SecureRandom.hex(4)}@#{tenant.host}")
      outside = seed_identity(tenant, "victim-#{SecureRandom.hex(4)}@unrelated.example.org")

      results = new_operation(tenant, unlink: true, dry_run: false).call

      statuses = results.to_h { |r| [r.account_id, r.status] }
      expect(statuses[inside[:account_id]]).to eq(:inside)
      expect(statuses[outside[:account_id]]).to eq(:unlinked)
      expect(identity_exists?(inside[:identity_id])).to be true
      expect(identity_exists?(outside[:identity_id])).to be false
      expect(db[:accounts].where(id: outside[:account_id]).count).to eq(1)
      expect(Onetime::Customer.find_by_extid(outside[:customer].extid)).not_to be_nil
      expect(Auth::Logging).to have_received(:log_auth_event).with(
        :omniauth_tenant_identity_unlinked,
        hash_including(
          level: :warn,
          domain_id: tenant.domain.identifier,
          org_id: tenant.org.objid,
          account_id: outside[:account_id],
          provider: tenant.provider,
          asserted_domain: 'unrelated.example.org',
          actor: 'cli',
        ),
      ).once

      again = new_operation(tenant, unlink: true, dry_run: false).call
      expect(again.map(&:status)).to eq([:inside])
    end
  end

  describe 'refusals' do
    it 'refuses a domain without an SSO config' do
      run    = SecureRandom.hex(6)
      owner  = Onetime::Customer.new(email: "owner-#{run}@audit-tenant-test.example.com")
      owner.save
      org    = Onetime::Organization.create!("Audit Org #{run}", owner, "contact-#{run}@audit-tenant-test.example.com")
      domain = Onetime::CustomDomain.parse("bare-#{run}.audit-tenant-test.example.com", org.objid)
      domain.save
      fixtures.push(owner, org, domain)

      expect { Auth::Operations::AuditTenantEmailDomains.new(domain: domain) }
        .to raise_error(Onetime::Problem, /no SSO config/)
    end
  end

  describe 'CLI: bin/ots sso audit-email-domains', :cli do
    def run_command(cmd, **kwargs)
      allow(cmd).to receive(:boot_application!)
      out  = StringIO.new
      orig = $stdout
      $stdout = out
      begin
        cmd.call(**kwargs)
      ensure
        $stdout = orig
      end
      out.string
    end

    it 'reports without --confirm and writes nothing (JSON)' do
      tenant  = build_tenant
      outside = seed_identity(tenant, "victim-#{SecureRandom.hex(4)}@unrelated.example.org")

      output  = run_command(Onetime::CLI::SsoAuditEmailDomainsCommand.new,
        domain: tenant.domain.display_domain, unlink: true, confirm: false, json: true)
      payload = JSON.parse(output)

      expect(payload['dry_run']).to be true
      expect(payload['unlink']).to be true
      expect(payload['issuer']).to eq(tenant_issuer)
      expect(payload['issuer_override']).to be false
      expect(payload['proof_basis']).to eq('override_only')
      # Under passthrough the basis line already says why the flag alone
      # does not count; the missing-pass list is for TXT strategies.
      expect(payload['verified_without_txt_pass']).to eq([])
      expect(payload['statistics']['unlink']).to eq(1)
      expect(payload['results'].first['status']).to eq('would_unlink')
      expect(payload['results'].first['asserted_domain']).to eq('unrelated.example.org')
      expect(identity_exists?(outside[:identity_id])).to be true
    end

    # Under a strategy that checks the TXT record, a domain counts without an
    # override once a passing check is on record. A domain verified with no
    # record (under passthrough before the switch, or before v0.26.14) does
    # not, and the command names it so the operator knows to re-verify.
    context 'under a validation strategy that checks the TXT record (approximated)' do
      before do
        @saved_domains_section         = OT.conf['features']['domains']
        OT.conf['features']['domains'] = (@saved_domains_section || {}).merge('validation_strategy' => 'approximated')
      end

      after { OT.conf['features']['domains'] = @saved_domains_section }

      it 'names the TXT basis, counts a recorded pass and names a verified domain without one (JSON)' do
        expect(Onetime::CustomDomain.ownership_proof_checked?).to be(true)

        tenant = build_tenant
        run    = SecureRandom.hex(4)
        add_org_domain(tenant, "txt-#{run}.example.com", verified: true, override: false, confirmed: true)
        legacy  = add_org_domain(tenant, "legacy-#{run}.example.com", verified: true, override: false)
        txt_row = seed_identity(tenant, "a@txt-#{run}.example.com")
        old_row = seed_identity(tenant, "b@legacy-#{run}.example.com")
        outside = seed_identity(tenant, "victim-#{SecureRandom.hex(4)}@unrelated.example.org")

        output  = run_command(Onetime::CLI::SsoAuditEmailDomainsCommand.new,
          domain: tenant.domain.display_domain, unlink: false, confirm: false, json: true)
        payload = JSON.parse(output)

        expect(payload['proof_basis']).to eq('txt_or_override')
        expect(payload['verified_without_txt_pass']).to eq([legacy.display_domain])
        statuses = payload['results'].to_h { |r| [r['account_id'], r['status']] }
        expect(statuses[txt_row[:account_id]]).to eq('inside')
        expect(statuses[old_row[:account_id]]).to eq('outside')
        expect(statuses[outside[:account_id]]).to eq('outside')
      end

      it 'prints the verified domains that have no TXT pass on record in text mode' do
        tenant = build_tenant
        run    = SecureRandom.hex(4)
        legacy = add_org_domain(tenant, "legacy-#{run}.example.com", verified: true, override: false)

        output = run_command(Onetime::CLI::SsoAuditEmailDomainsCommand.new,
          domain: tenant.domain.display_domain, unlink: false, confirm: false, json: false)

        expect(output).to include('Proven by:    TXT ownership check or Colonel override')
        expect(output).to include("No TXT pass:  #{legacy.display_domain}")
        expect(output).to include('bin/ots domains verify --all')
      end
    end

    it 'unlinks with --unlink --confirm (JSON)' do
      tenant  = build_tenant
      outside = seed_identity(tenant, "victim-#{SecureRandom.hex(4)}@unrelated.example.org")

      output  = run_command(Onetime::CLI::SsoAuditEmailDomainsCommand.new,
        domain: tenant.domain.display_domain, unlink: true, confirm: true, json: true)
      payload = JSON.parse(output)

      expect(payload['dry_run']).to be false
      expect(payload['statistics']['unlink']).to eq(1)
      expect(payload['results'].first['status']).to eq('unlinked')
      expect(identity_exists?(outside[:identity_id])).to be false
    end

    it 'prints the table and the follow-up command in text mode' do
      tenant = build_tenant
      seed_identity(tenant, "victim-#{SecureRandom.hex(4)}@unrelated.example.org")

      output = run_command(Onetime::CLI::SsoAuditEmailDomainsCommand.new,
        domain: tenant.domain.display_domain, unlink: false, confirm: false, json: false)

      expect(output).to include('Tenant SSO Email Domain Audit')
      expect(output).to include('Proven by:    Colonel override only (validation strategy makes no TXT check)')
      expect(output).to include('outside')
      expect(output).to include("bin/ots sso audit-email-domains #{tenant.domain.display_domain} --unlink --confirm")
    end

    it 'keeps --issuer, shell-quoted, on the follow-up commands it prints (text)' do
      tenant = build_tenant
      host   = tenant.domain.display_domain
      piped  = "#{tenant.domain.identifier}|https://audit-idp.test/#{SecureRandom.hex(4)}"
      seed_identity(tenant, "victim-#{SecureRandom.hex(4)}@unrelated.example.org", issuer: stamped_issuer)
      seed_identity(tenant, "victim-#{SecureRandom.hex(4)}@unrelated.example.org", issuer: piped)

      report  = run_command(Onetime::CLI::SsoAuditEmailDomainsCommand.new,
        domain: host, issuer: stamped_issuer, unlink: false, confirm: false, json: false)
      preview = run_command(Onetime::CLI::SsoAuditEmailDomainsCommand.new,
        domain: host, issuer: stamped_issuer, unlink: true, confirm: false, json: false)
      quoted  = run_command(Onetime::CLI::SsoAuditEmailDomainsCommand.new,
        domain: host, issuer: piped, unlink: false, confirm: false, json: false)

      follow_up = "bin/ots sso audit-email-domains #{host} --unlink --confirm --issuer #{stamped_issuer}"
      expect(report).to include(follow_up)
      expect(preview).to include('Preview only.')
      expect(preview).to include(follow_up)
      expect(quoted).to include("--unlink --confirm --issuer #{Shellwords.escape(piped)}")
    end

    it 'says a zero-row scan may miss rows stamped with another issuer (text)' do
      tenant = build_tenant
      seed_identity(tenant, "victim-#{SecureRandom.hex(4)}@unrelated.example.org", issuer: stamped_issuer)

      output = run_command(Onetime::CLI::SsoAuditEmailDomainsCommand.new,
        domain: tenant.domain.display_domain, unlink: false, confirm: false, json: false)

      expect(output).to include("Issuer:       #{tenant_issuer}\n")
      expect(output).not_to include('(from --issuer)')
      expect(output).to include('Scanned 0 identity row(s) under this issuer')
      expect(output).to include('Rows that backfill-issuer --issuer stamped with a different value are outside this scan')
      expect(output).to include('re-run with --issuer')
    end

    it 'scans the rows stamped with the --issuer value and marks the override (text and JSON)' do
      tenant  = build_tenant
      outside = seed_identity(tenant, "victim-#{SecureRandom.hex(4)}@unrelated.example.org", issuer: stamped_issuer)

      text = run_command(Onetime::CLI::SsoAuditEmailDomainsCommand.new,
        domain: tenant.domain.display_domain, issuer: stamped_issuer, unlink: false, confirm: false, json: false)

      expect(text).to include("Issuer:       #{stamped_issuer} (from --issuer)")
      expect(text).to include('Scanned 1 identity row(s) under this issuer')
      expect(text).not_to include('outside this scan')

      payload = JSON.parse(run_command(Onetime::CLI::SsoAuditEmailDomainsCommand.new,
        domain: tenant.domain.display_domain, issuer: stamped_issuer, unlink: false, confirm: false, json: true))

      expect(payload['issuer']).to eq(stamped_issuer)
      expect(payload['issuer_override']).to be true
      expect(payload['statistics']['scanned']).to eq(1)
      expect(payload['results'].first['account_id']).to eq(outside[:account_id])
      expect(payload['results'].first['status']).to eq('outside')
      expect(payload['results'].first['issuer']).to eq(stamped_issuer)
      expect(identity_exists?(outside[:identity_id])).to be true
    end

    it 'with --unlink --confirm --issuer still refuses a row whose signup_domain_id names another domain (JSON)' do
      tenant = build_tenant
      other  = seed_identity(tenant, "q@unrelated.example.org", signup: 'cd_somewhere_else', issuer: stamped_issuer)

      payload = JSON.parse(run_command(Onetime::CLI::SsoAuditEmailDomainsCommand.new,
        domain: tenant.domain.display_domain, issuer: stamped_issuer, unlink: true, confirm: true, json: true))

      expect(payload['dry_run']).to be false
      expect(payload['issuer_override']).to be true
      expect(payload['statistics']['scanned']).to eq(1)
      expect(payload['statistics']['unlink']).to eq(0)
      expect(payload['statistics']['skipped_ambiguous_origin']).to eq(1)
      expect(payload['results'].first['status']).to eq('skipped_ambiguous_origin')
      expect(identity_exists?(other[:identity_id])).to be true
      expect(Auth::Logging).not_to have_received(:log_auth_event).with(:omniauth_tenant_identity_unlinked, anything)
    end

    it 'is listed by the group root' do
      output = run_command(Onetime::CLI::SsoCommand.new)

      expect(output).to include('bin/ots sso audit-email-domains DOMAIN')
    end
  end
end

# frozen_string_literal: true

# RISK-2026-10-10-01 (#4734): a tenant's identity provider could mint a
# verified canonical-pool account for any address with no OTS account yet.
# The tenant allowlist did not help (it is the tenant's own choice, and an
# empty list is allow-all). Tenant SSO now creates an account only for an
# address inside a custom domain the organization has proven by TXT
# ownership check; the allowlist selects among those domains. An identity
# already bound to an account keeps signing in and is recorded.
#
# Derived from the probe in docs/security/audits/security-audit-2026-10-10.md
# (P1), which passed against baseline 3a30ad2eeb and must fail now.
#
# Run with full-sqlite or full-pg-agnostic (org SSO enabled, OIDC route
# registered).
require_relative '../../spec_helper'
require_relative '../../support/oauth_flow_helper'

RSpec.describe 'Tenant SSO verified email domains (#4734)', type: :integration do
  include Rack::Test::Methods
  include_context 'domains enabled'

  before(:all) { boot_onetime_app }

  let(:run_id) { SecureRandom.hex(6) }
  let(:host) { "g3-#{run_id}.tenant.example.com" }
  let(:uid) { "oid-#{SecureRandom.uuid}" }
  let!(:tenant) { setup_oauth_test_domain(host) }
  # An address in a namespace the tenant has not proven and that has no account.
  let(:outside_email) { "victim-#{run_id}@unrelated.example.org" }
  # An address at the tenant's own, TXT-verified custom domain.
  let(:inside_email) { "member-#{run_id}@#{host}" }

  before do
    configure_allowed_domains(nil)
    allow(Auth::Logging).to receive(:log_auth_event).and_call_original
    @extra_domains = []
    @minted_emails = []
  end

  after do
    teardown_mock_auth
    @minted_emails.uniq.each do |email|
      customer = Onetime::Customer.find_by_email(email)
      next unless customer

      Onetime::OrganizationMembership.find_by_org_customer(tenant[:org].objid, customer.objid)&.destroy!
      customer.destroy!
    end
    @extra_domains.each do |domain|
      domain.destroy! if domain.exists?
    rescue StandardError => ex
      warn "[#4734 spec] domain cleanup failed: #{ex.class}: #{ex.message}"
    end
    cleanup_oauth_test_fixtures
    clear_auth_database
  end

  # A second custom domain of the tenant organization, listed in its domains
  # set, with the ownership axis in the given state. Nothing on the serving
  # axis: proving an email namespace never requires pointing it at us.
  def add_org_domain(display_domain, verified:)
    domain                    = Onetime::CustomDomain.parse(display_domain, tenant[:org].objid)
    domain.ownership_verified = verified
    domain.save
    tenant[:org].add_domain(domain)
    @extra_domains << domain
    domain
  end

  # Entra-shaped claim set via the mock strategy: tid+oid identity, an `email`
  # claim and no email_verified.
  def claim_hash(email)
    OmniAuth::AuthHash.new(
      provider: 'oidc',
      uid: uid,
      info: { email: email, name: 'Probe User' },
      credentials: { token: 'mock_access_token', expires: false },
      extra: {
        raw_info: {
          sub: uid, oid: uid, tid: "tenant-#{run_id}",
          preferred_username: "probe@#{run_id}.onmicrosoft.com",
        },
      },
    )
  end

  def tenant_callback(email)
    @minted_emails << email
    enable_omniauth_test_mode
    OmniAuth.config.mock_auth[:oidc] = claim_hash(email)
    clear_body_headers
    header 'Host', host
    post '/auth/sso/oidc'
    expect(last_response.status).to eq(302), last_response.body
    expect(last_request.env['rack.session']['omniauth_tenant_domain_id']).to eq(tenant[:domain].identifier)
    clear_body_headers
    header 'Host', host
    post '/auth/sso/oidc/callback'
    expect(last_response.status).not_to eq(404), 'SSO route must be registered'
  end

  def expect_minted_verified_account(email)
    expect(last_response.status).to eq(302), last_response.body
    expect(last_response.location.to_s).not_to include('auth_error='), last_response.location.to_s
    account = auth_db[:accounts].where(email: email).first
    expect(account).not_to be_nil
    expect(account[:status_id]).to eq(AuthTestConstants::STATUS_VERIFIED)
    customer = Onetime::Customer.find_by_email(email)
    expect(customer).not_to be_nil
    expect(customer.provisioning_origin.to_s).to eq('sso_jit')
    expect(Onetime::OrganizationMembership.find_by_org_customer(tenant[:org].objid, customer.objid)).not_to be_nil
    expect(last_request.env['rack.session'].to_h).to include('authenticated' => true, 'account_id' => account[:id])
    account
  end

  def expect_nothing_minted(email)
    expect_auth_error_redirect('domain_not_allowed')
    expect(auth_db[:accounts].where(email: email).count).to eq(0)
    expect(auth_db[:account_identities].where(provider: 'oidc', uid: uid).count).to eq(0)
    expect(Onetime::Customer.find_by_email(email)).to be_nil
    expect(last_request.env['rack.session']['authenticated']).not_to be(true)
  end

  describe 'an address outside every domain the organization has proven' do
    [[], ['unrelated.example.org']].each do |allowlist|
      it "is refused before any account exists (allowlist #{allowlist.inspect})" do
        tenant[:sso_config].allowed_domains = allowlist
        tenant[:sso_config].save

        tenant_callback(outside_email)

        expect_nothing_minted(outside_email)
        expect(Auth::Logging).to have_received(:log_auth_event)
          .with(:omniauth_tenant_email_domain_unverified, hash_including(
            outcome: :refused,
            reason: :email_domain_unverified,
            domain_id: tenant[:domain].identifier,
            org_id: tenant[:org].objid,
            asserted_domain: 'unrelated.example.org',
          ))
      end
    end

    it 'is refused even at the registrable domain above the tenant custom domain' do
      # The TXT record for g3-<x>.tenant.example.com proves that name, not
      # who answers mail at tenant.example.com.
      above = "victim-#{run_id}@tenant.example.com"

      tenant_callback(above)

      expect_nothing_minted(above)
    end

    it 'is refused while the second custom domain that would prove it is unverified' do
      pending = add_org_domain("mail-#{run_id}.example.net", verified: false)
      email   = "user-#{run_id}@#{pending.display_domain}"

      tenant_callback(email)

      expect_nothing_minted(email)
    end
  end

  describe 'an address inside a proven domain' do
    it 'is minted at the tenant custom domain itself' do
      tenant_callback(inside_email)

      expect_minted_verified_account(inside_email)
      expect(Auth::Logging).not_to have_received(:log_auth_event)
        .with(:omniauth_tenant_email_domain_unverified, anything)
    end

    it 'is minted below the tenant custom domain' do
      email = "user-#{run_id}@mail.#{host}"

      tenant_callback(email)

      expect_minted_verified_account(email)
    end

    it 'is minted in a second custom domain the organization has verified, with the allowlist selecting it' do
      mail  = add_org_domain("mail-#{run_id}.example.net", verified: true)
      email = "user-#{run_id}@#{mail.display_domain}"
      tenant[:sso_config].allowed_domains = [mail.display_domain]
      tenant[:sso_config].save

      tenant_callback(email)

      expect_minted_verified_account(email)
    end

    it 'is still refused when the allowlist does not select its domain' do
      mail  = add_org_domain("mail-#{run_id}.example.net", verified: true)
      email = "user-#{run_id}@#{mail.display_domain}"
      tenant[:sso_config].allowed_domains = [host]
      tenant[:sso_config].save

      tenant_callback(email)

      expect_auth_error_redirect('domain_not_allowed')
      expect(auth_db[:accounts].where(email: email).count).to eq(0)
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:omniauth_tenant_domain_rejected, hash_including(reason: :domain_not_allowed))
    end
  end

  describe 'an identity already bound to an account' do
    it 'keeps signing in after the proof of its domain lapses, and is recorded' do
      mail  = add_org_domain("mail-#{run_id}.example.net", verified: true)
      email = "user-#{run_id}@#{mail.display_domain}"
      tenant_callback(email)
      account = expect_minted_verified_account(email)

      clear_cookies
      mail.ownership_verified = false
      mail.save

      tenant_callback(email)

      expect(last_response.status).to eq(302), last_response.body
      expect(last_response.location.to_s).not_to include('auth_error='), last_response.location.to_s
      expect(last_request.env['rack.session'].to_h).to include('authenticated' => true, 'account_id' => account[:id])
      expect(auth_db[:account_identities].where(provider: 'oidc', uid: uid).all)
        .to contain_exactly(hash_including(account_id: account[:id]))
      expect(Auth::Logging).to have_received(:log_auth_event)
        .with(:omniauth_tenant_email_domain_unverified, hash_including(
          outcome: :signed_in,
          reason: :email_domain_unverified,
          domain_id: tenant[:domain].identifier,
          asserted_domain: mail.display_domain,
        ))
    end
  end
end

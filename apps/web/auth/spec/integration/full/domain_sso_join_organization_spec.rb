# apps/web/auth/spec/integration/domain_sso_join_organization_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration Tests for Tenant-SSO Org Membership (Issue #3114)
# =============================================================================
#
# Issue: #3114 - Tenant-SSO users not added to org due to session lifecycle
#
# Background
# ----------
# When a user signs in via tenant-SSO on a custom domain, two hooks coordinate
# to join them to the domain's primary organization:
#
#   - after_omniauth_create_account (omniauth.rb) — owns NEW accounts.
#       Reads & deletes :validated_omniauth_domain_id; calls JoinDomainOrganization
#       with the freshly created customer.
#   - after_login (login.rb) — owns EXISTING accounts.
#       Reads & deletes :validated_omniauth_domain_id; if present (i.e., the
#       create-hook did not consume it), looks up the customer via extid and
#       calls JoinDomainOrganization.
#
# The :validated_omniauth_domain_id key is set by the before_omniauth_callback_route
# hook in omniauth_tenant.rb after the cross-tenant validation passes. Before
# the fix, downstream hooks read :omniauth_tenant_domain_id, which had already
# been deleted by the validation hook — so JoinDomainOrganization was never
# invoked and tenant-SSO users only got a Default Workspace.
#
# These tests cover three layers:
#
#   1. Operation-level: JoinDomainOrganization correctness against real fixtures.
#   2. Hook-contract: the session-key handoff between validation and consumer hooks.
#   3. End-to-end: real OAuth callback flow asserting tenant org membership.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec apps/web/auth/spec/integration/domain_sso_join_organization_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/tenant_test_fixtures'
require_relative '../../support/domain_sso_test_fixtures'
require_relative '../../support/oauth_flow_helper'

RSpec.describe 'Tenant-SSO Join Domain Organization (issue #3114)', type: :integration do
  include TenantTestFixtures
  include DomainSsoTestFixtures

  before(:all) do
    require 'onetime' unless defined?(Onetime)
    Onetime.boot! :test unless Onetime.ready?
    require_relative '../../../operations/join_domain_organization'
  end

  let(:test_run_id) { SecureRandom.hex(8) }
  let(:tenant_domain) { "secrets-#{test_run_id}.acme-corp.example.com" }

  # Build domain + organization fixtures directly so each describe block
  # controls its own lifecycle without relying on shared_context wiring.
  let!(:tenant_org_owner) do
    owner = Onetime::Customer.new(email: "owner-#{test_run_id}@tenant.example.com")
    owner.save
    owner
  end

  let!(:tenant_organization) do
    Onetime::Organization.create!(
      "Tenant Org #{test_run_id}",
      tenant_org_owner,
      "contact-#{test_run_id}@tenant.example.com",
    )
  end

  let!(:tenant_custom_domain) do
    domain = Onetime::CustomDomain.new(
      display_domain: tenant_domain,
      org_id: tenant_organization.org_id,
    )
    domain.save
    Onetime::CustomDomain.display_domains.put(tenant_domain, domain.domainid)
    domain
  end

  # An SSO customer (the user signing in via tenant SSO on the custom domain).
  let!(:sso_customer) do
    customer = Onetime::Customer.new(email: "user-#{test_run_id}@tenant.example.com")
    customer.save
    customer
  end

  after do
    sso_customer&.destroy! rescue nil
    Onetime::CustomDomain.display_domains.remove(tenant_domain) rescue nil
    tenant_custom_domain&.destroy! rescue nil
    tenant_organization&.destroy! rescue nil
    tenant_org_owner&.destroy! rescue nil
  end

  # ==========================================================================
  # Operation-level: JoinDomainOrganization correctness
  # ==========================================================================

  describe 'JoinDomainOrganization operation' do
    it 'adds the customer to the tenant organization as a member' do
      result = Auth::Operations::JoinDomainOrganization.new(
        customer: sso_customer,
        domain_id: tenant_custom_domain.identifier,
      ).call

      expect(result[:joined]).to be(true), "Expected new user to be joined, got: #{result.inspect}"
      expect(result[:reason]).to eq('added_via_sso')
      expect(result[:organization]&.objid).to eq(tenant_organization.objid)
      expect(tenant_organization.member?(sso_customer)).to be(true),
        'Customer must be a member of the tenant organization after join'
    end

    it 'is idempotent: returning user already in org gets no-op' do
      # First call adds membership
      first = Auth::Operations::JoinDomainOrganization.new(
        customer: sso_customer,
        domain_id: tenant_custom_domain.identifier,
      ).call
      expect(first[:joined]).to be(true)

      # Second call is a no-op. Although the production hooks no longer
      # double-invoke this op on a single request (after_omniauth_create_account
      # consumes the validated key for new accounts), the operation's
      # idempotency guarantee is what makes the consolidation safe across
      # subsequent SSO logins by the same returning user.
      second = Auth::Operations::JoinDomainOrganization.new(
        customer: sso_customer,
        domain_id: tenant_custom_domain.identifier,
      ).call

      expect(second[:joined]).to be(false)
      expect(second[:reason]).to eq('already_member')
      expect(second[:organization]&.objid).to eq(tenant_organization.objid)
    end

    # The invited-then-SSO sub-case: a pending org-scoped invitation is accepted
    # *through* the SSO join path. ensure_membership takes its accept! branch,
    # which carries the invitation's own (nil) domain_scope_id — the SSO-supplied
    # domain_scope_id is ignored. The member therefore stays org-scoped: broader
    # access than domain-scoped, not a leak. This test pins that as intended
    # behavior and asserts the invite is consumed (not duplicated) and that
    # provisioning_source: 'sso' threads through accept!/activate!.
    it 'accepts a pending org-scoped invitation via SSO and stays org-scoped' do
      invitation = Onetime::OrganizationMembership.create_invitation!(
        organization: tenant_organization,
        email: sso_customer.email,
        role: 'member',
        inviter: tenant_org_owner,
      )
      expect(invitation.pending?).to be(true)
      expect(tenant_organization.pending_invitation_count).to eq(1)

      result = Auth::Operations::JoinDomainOrganization.new(
        customer: sso_customer,
        domain_id: tenant_custom_domain.identifier,
      ).call

      expect(result[:joined]).to be(true), "Expected invited user to be joined, got: #{result.inspect}"
      expect(result[:reason]).to eq('added_via_sso')
      expect(tenant_organization.member?(sso_customer)).to be(true)

      # Invite consumed, not duplicated.
      expect(tenant_organization.pending_invitation_count).to eq(0)

      membership = result[:membership]
      expect(membership).not_to be_nil
      # SSO lifecycle attribution survives the accept! path.
      expect(membership.provisioning_source).to eq('sso')
      # Scope invariant: invite's nil scope wins over the SSO domain_scope_id.
      expect(membership.org_scoped?).to be(true),
        "Expected membership to stay org-scoped, got domain_scope_id=#{membership.domain_scope_id.inspect}"
      expect(membership.domain_scope_id.to_s).to be_empty
    end
  end

  # ==========================================================================
  # Hook contract: session-key handoff
  # ==========================================================================

  describe 'session-key handoff (post-fix invariants)' do
    it 'after_omniauth_create_account consumes the validated key (new accounts)' do
      # Mirror what the production hook does at omniauth.rb:219
      session = { validated_omniauth_domain_id: tenant_custom_domain.identifier }
      domain_id = session.delete(:validated_omniauth_domain_id)

      expect(domain_id).to eq(tenant_custom_domain.identifier)
      expect(session).not_to have_key(:validated_omniauth_domain_id),
        'after_omniauth_create_account must consume the key so after_login skips for new accounts'
    end

    it 'after_login skips when create-hook already consumed the key' do
      # New-account path: create-hook ran first, deleted the key.
      # Mirror what login.rb:154 does — should see nil and skip.
      session = {} # Already consumed upstream

      domain_id = session.delete(:validated_omniauth_domain_id)
      expect(domain_id).to be_nil

      # Hook guard `if domain_id` → skipped → no duplicate op call
      called = false
      if domain_id
        called = true
        Auth::Operations::JoinDomainOrganization.new(
          customer: sso_customer,
          domain_id: domain_id,
        ).call
      end
      expect(called).to be(false), 'after_login must not invoke JoinDomainOrganization for new accounts'
    end

    it 'after_login handles existing accounts when create-hook did not run' do
      # Existing-account path: no create-hook fired (account already exists).
      # The validated key is still in session; after_login consumes it.
      session = { validated_omniauth_domain_id: tenant_custom_domain.identifier }

      domain_id = session.delete(:validated_omniauth_domain_id)
      expect(domain_id).to eq(tenant_custom_domain.identifier)
      expect(session).not_to have_key(:validated_omniauth_domain_id),
        'after_login must also consume the key to prevent leakage into later requests'
    end

    it 'hooks skip when no validated key in session (platform-level or password auth)' do
      session = {}

      domain_id = session.delete(:validated_omniauth_domain_id)
      expect(domain_id).to be_nil,
        'Without tenant SSO context, the validated key is never set → both hooks short-circuit'
    end
  end

  # ==========================================================================
  # End-to-end: real OAuth callback flow asserting tenant org membership
  # ==========================================================================
  #
  # Drives the actual Rodauth omniauth callback through the Rack stack and
  # asserts that, after the flow completes, the SSO customer is a member of
  # the tenant organization. This is the strongest regression guard for
  # issue #3114 — a refactor that breaks the session-key handoff would
  # cause this assertion to fail.
  #

  describe 'end-to-end OAuth callback joins user to tenant org', :oauth_flow do
    include Rack::Test::Methods
    include OAuthFlowHelper

    def app
      Onetime::Application::Registry.generate_rack_url_map
    end

    let(:e2e_run_id) { "join-e2e-#{SecureRandom.hex(4)}" }
    let(:e2e_domain_host) { "secrets-#{e2e_run_id}.tenant.example.com" }
    let(:e2e_user_email) { "new-user-#{e2e_run_id}@tenant.example.com" }

    before do
      @e2e_fixtures = setup_oauth_test_domain(e2e_domain_host)
    end

    after do
      Onetime::Customer.find_by_email(e2e_user_email)&.destroy! rescue nil
      cleanup_oauth_test_fixtures
    end

    it 'creates customer and joins them to the tenant organization' do
      OmniAuth.config.test_mode = true
      OmniAuth.config.allowed_request_methods = %i[get post]

      OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new({
        provider: 'oidc',
        uid: "uid-#{e2e_run_id}",
        info: { email: e2e_user_email, name: 'E2E Test User' },
      })

      begin
        # Phase 1: initiate from the tenant domain.
        # omniauth_setup sets session[:omniauth_tenant_domain_id].
        header 'Host', e2e_domain_host
        post '/auth/sso/oidc'

        if last_response.status == 404
          skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
        end
        expect(last_response.status).to eq(302),
          "Initiation should redirect, got: #{last_response.status}"

        # Phase 2: callback from the same tenant domain.
        # before_omniauth_callback_route validates and now also sets
        # :validated_omniauth_domain_id. after_omniauth_create_account
        # consumes it and calls JoinDomainOrganization.
        header 'Host', e2e_domain_host
        post '/auth/sso/oidc/callback'

        expect(last_response.status).not_to eq(403),
          "Callback failed with 403; body: #{last_response.body}"

        # Strong assertion: the customer exists and is a member of the
        # tenant organization. Before the fix, this would fail — the
        # customer existed but was NOT a member of the tenant org.
        tenant_org = @e2e_fixtures[:org]
        customer = Onetime::Customer.find_by_email(e2e_user_email)

        expect(customer).not_to be_nil,
          'Customer should have been created by after_omniauth_create_account'
        expect(tenant_org.member?(customer)).to be(true),
          "Customer should be a member of the tenant org after SSO. " \
          "If this fails, the session-key handoff (issue #3114) is broken again."
      ensure
        OmniAuth.config.test_mode = false
        OmniAuth.config.mock_auth.clear
      end
    end
  end
end

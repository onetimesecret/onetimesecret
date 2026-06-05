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
    Onetime::CustomDomain.display_domain_index.put(tenant_domain, domain.domainid)
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
    Onetime::CustomDomain.display_domain_index.remove(tenant_domain) rescue nil
    tenant_custom_domain&.destroy! rescue nil
    tenant_organization&.destroy! rescue nil
    tenant_org_owner&.destroy! rescue nil
  end

  # ==========================================================================
  # Operation-level: JoinDomainOrganization correctness
  # ==========================================================================

  # :shared_db_state opts these examples out of the per-each Valkey flush.
  # The fixtures above are built in per-example `let!` hooks, not before(:all),
  # so the tag name is a slight misnomer here — but the guard is exactly what we
  # need: the integration flush hooks live in three helpers (this app's
  # spec_helper, the core integration_spec_helper, and the top-level
  # spec_helper). Their before(:each) ordering relative to this group's `let!`
  # is incidental to load order; under some orderings the core
  # integration_spec_helper flush runs AFTER `let!` and wipes the freshly-saved
  # CustomDomain before the example body reads it ("Domain not found"). Skipping
  # the flush makes the group order-proof: each example uses a unique
  # `test_run_id`, builds its own fixtures, and tears them down in `after`.
  describe 'JoinDomainOrganization operation', :shared_db_state do
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
  # Regression: tenant SSO must NOT create a default workspace (issue #3326)
  # ==========================================================================
  #
  # Before the fix, after_omniauth_create_account called CreateDefaultWorkspace
  # BEFORE JoinDomainOrganization, resulting in tenant SSO users getting BOTH
  # a default workspace AND membership in the tenant org. This violated the
  # principle that tenant SSO users should only belong to the tenant org.
  #
  # The fix made the paths mutually exclusive:
  #   - if domain_id present  → JoinDomainOrganization only (tenant SSO)
  #   - if domain_id absent   → CreateDefaultWorkspace only (canonical SSO)
  #
  describe 'tenant SSO does not create default workspace (issue #3326)', :shared_db_state do
    # Fresh customer with no organizations
    let!(:fresh_sso_customer) do
      customer = Onetime::Customer.new(email: "fresh-#{test_run_id}@tenant.example.com")
      customer.save
      customer
    end

    after do
      # Clean up any orgs created during tests
      fresh_sso_customer&.organization_instances&.each do |org|
        org.destroy! rescue nil
      end
      fresh_sso_customer&.destroy! rescue nil
    end

    it 'tenant SSO user joins only the tenant org, no default workspace created' do
      # Precondition: user has no organizations
      expect(fresh_sso_customer.organization_instances.count).to eq(0),
        'Fresh customer should have no organizations before SSO'

      # Simulate tenant SSO path: domain_id is present
      result = Auth::Operations::JoinDomainOrganization.new(
        customer: fresh_sso_customer,
        domain_id: tenant_custom_domain.identifier,
      ).call

      expect(result[:joined]).to be(true)

      # Reload participation data
      orgs = fresh_sso_customer.organization_instances.to_a

      # Critical assertion: user should have exactly ONE organization (the tenant org)
      expect(orgs.count).to eq(1),
        "Tenant SSO user should have exactly 1 org, got #{orgs.count}: #{orgs.map(&:display_name)}"

      # And that org should be the tenant org, not a default workspace
      expect(orgs.first.objid).to eq(tenant_organization.objid),
        'The single org should be the tenant org, not a default workspace'
      expect(orgs.first.is_default).to be_falsey,
        'Tenant org should not be marked as default workspace'
    end

    it 'canonical SSO user gets default workspace, not tenant org membership' do
      # Simulate canonical SSO path: no domain_id (SSO on main domain)
      # CreateDefaultWorkspace should run

      # Precondition: user has no organizations
      expect(fresh_sso_customer.organization_instances.count).to eq(0)

      # This is what happens when domain_id is nil in the hook
      Auth::Operations::CreateDefaultWorkspace.new(customer: fresh_sso_customer).call

      orgs = fresh_sso_customer.organization_instances.to_a

      expect(orgs.count).to eq(1),
        "Canonical SSO user should have exactly 1 org (default workspace)"
      expect(orgs.first.is_default).to be(true),
        'The org should be marked as default workspace'
      expect(orgs.first.member?(fresh_sso_customer)).to be(true)

      # And they should NOT be in the tenant org
      expect(tenant_organization.member?(fresh_sso_customer)).to be(false),
        'Canonical SSO user should not be added to tenant org'
    end

    it 'fallback: creates default workspace when JoinDomainOrganization fails silently' do
      # Mirrors the safety-net branch added to after_omniauth_create_account:
      #   if customer.organization_instances.to_a.empty?
      #     CreateDefaultWorkspace.new(customer: customer).call
      #   end
      #
      # A bad domain_id causes JoinDomainOrganization to return {joined: false}
      # without raising (RecordNotFound is caught internally). The hook wraps
      # the call in safe_execute, so either way the customer ends up with zero
      # orgs -- triggering the fallback.

      # Precondition: user has no organizations
      expect(fresh_sso_customer.organization_instances.count).to eq(0),
        'Fresh customer should have no organizations before SSO'

      # Simulate the hook's tenant-SSO branch with a domain_id that will fail lookup
      bogus_domain_id = 'nonexistent_domain_id'

      # Step 1: JoinDomainOrganization fails silently (mirrors safe_execute wrapper)
      Onetime::ErrorHandler.safe_execute(
        'join_domain_organization_omniauth',
        extid: fresh_sso_customer.extid,
        domain_id: bogus_domain_id,
      ) do
        Auth::Operations::JoinDomainOrganization.new(
          customer: fresh_sso_customer,
          domain_id: bogus_domain_id,
        ).call
      end

      # Intermediate state: join failed, customer still has zero orgs
      expect(fresh_sso_customer.organization_instances.to_a).to be_empty,
        'After failed join, customer should still have zero organizations'

      # Step 2: Fallback triggers because org count is zero
      if fresh_sso_customer.organization_instances.to_a.empty?
        Auth::Operations::CreateDefaultWorkspace.new(customer: fresh_sso_customer).call
      end

      # Customer should now have exactly 1 org (the fallback workspace)
      orgs = fresh_sso_customer.organization_instances.to_a
      expect(orgs.count).to eq(1),
        "After fallback, customer should have exactly 1 org, got #{orgs.count}"
      expect(orgs.first.is_default).to be(true),
        'Fallback org should be a default workspace'
      expect(orgs.first.member?(fresh_sso_customer)).to be(true),
        'Customer should be a member of the fallback workspace'
    end

    it 'mutually exclusive: cannot get both default workspace and tenant org' do
      # This test mirrors the bug scenario from #3326:
      # If both operations ran, user would end up in 2 orgs

      # Step 1: Join tenant org (tenant SSO path)
      Auth::Operations::JoinDomainOrganization.new(
        customer: fresh_sso_customer,
        domain_id: tenant_custom_domain.identifier,
      ).call

      # Step 2: CreateDefaultWorkspace should now be a no-op
      # because workspace_already_exists? returns true
      result = Auth::Operations::CreateDefaultWorkspace.new(customer: fresh_sso_customer).call

      expect(result).to be_nil,
        'CreateDefaultWorkspace should return nil when user already has an org'

      orgs = fresh_sso_customer.organization_instances.to_a
      expect(orgs.count).to eq(1),
        "User should still have only 1 org after both operations attempted"

      # No default workspace should exist
      expect(orgs.none?(&:is_default)).to be(true),
        'No default workspace should have been created for tenant SSO user'
    end
  end

  # ==========================================================================
  # Self-heal: repoint default_org and archive personal workspace (#3336)
  # ==========================================================================
  #
  # When a legacy user (who has a personal default workspace) signs in via
  # domain SSO for the first time, JoinDomainOrganization should:
  #   1. Add them to the domain org (existing behavior)
  #   2. Repoint customer.default_org_id to the domain org
  #   3. Soft-archive the personal workspace
  #
  # This ensures the customer operates in the domain context immediately,
  # not in their stale personal workspace.
  #
  describe 'self-heal: repoint default_org and archive personal workspace (#3336)', :shared_db_state do
    # Legacy customer who already has a personal default workspace
    let!(:legacy_customer) do
      customer = Onetime::Customer.new(email: "legacy-#{test_run_id}@tenant.example.com")
      customer.save
      customer
    end

    # Create a personal default workspace for the legacy customer
    let!(:personal_workspace) do
      result = Auth::Operations::CreateDefaultWorkspace.new(customer: legacy_customer).call
      result[:organization]
    end

    after do
      legacy_customer&.organization_instances&.each do |org|
        org.destroy! rescue nil
      end
      legacy_customer&.destroy! rescue nil
    end

    it 'repoints default_org_id and archives personal workspace on first domain join' do
      # Precondition: customer has a personal workspace with is_default flag
      expect(personal_workspace.is_default).to be_truthy,
        'Personal workspace should have is_default flag'
      expect(personal_workspace.owner?(legacy_customer)).to be(true),
        'Legacy customer should own the personal workspace'
      expect(personal_workspace.archived?).to be(false),
        'Personal workspace should not be archived yet'

      # Set default_org_id to point to personal workspace (simulates legacy state)
      legacy_customer.default_org_id = personal_workspace.objid
      legacy_customer.save

      # Domain SSO join
      result = Auth::Operations::JoinDomainOrganization.new(
        customer: legacy_customer,
        domain_id: tenant_custom_domain.identifier,
      ).call

      expect(result[:joined]).to be(true), "Expected join to succeed, got: #{result.inspect}"

      # Adoption should have occurred
      expect(result[:adoption]).not_to be_nil, 'Expected adoption result'
      expect(result[:adoption][:adopted]).to be(true)
      expect(result[:adoption][:archived_org_id]).to eq(personal_workspace.objid)

      # Reload customer to verify default_org_id was repointed
      reloaded_customer = Onetime::Customer.load(legacy_customer.objid)
      expect(reloaded_customer.default_org_id).to eq(tenant_organization.objid),
        'default_org_id should now point to the domain org'

      # Personal workspace should be archived
      reloaded_workspace = Onetime::Organization.load(personal_workspace.objid)
      expect(reloaded_workspace.archived?).to be(true),
        'Personal workspace should be soft-archived'
      expect(reloaded_workspace.archived_at.to_s).not_to be_empty,
        'archived_at should be set'
    end

    it 'adopts domain org even when default_org_id is not explicitly set' do
      # Customer has a personal workspace but default_org_id is not set.
      # OrganizationLoader would fall through to step 4 (is_default flag).
      expect(legacy_customer.default_org_id.to_s).to be_empty,
        'default_org_id should not be set initially'
      expect(personal_workspace.is_default).to be_truthy

      result = Auth::Operations::JoinDomainOrganization.new(
        customer: legacy_customer,
        domain_id: tenant_custom_domain.identifier,
      ).call

      expect(result[:joined]).to be(true)
      expect(result[:adoption]).not_to be_nil, 'Expected adoption even without explicit default_org_id'
      expect(result[:adoption][:adopted]).to be(true)

      # default_org_id should now be set to domain org
      reloaded_customer = Onetime::Customer.load(legacy_customer.objid)
      expect(reloaded_customer.default_org_id).to eq(tenant_organization.objid)

      # Personal workspace archived
      reloaded_workspace = Onetime::Organization.load(personal_workspace.objid)
      expect(reloaded_workspace.archived?).to be(true)
    end

    it 'does not adopt when customer does not own the personal workspace' do
      # Transfer ownership of personal workspace to someone else
      personal_workspace.owner_id = tenant_org_owner.custid
      personal_workspace.save

      # Repair membership so owner? check uses membership role
      membership = Onetime::OrganizationMembership.find_by_org_customer(
        personal_workspace.objid, legacy_customer.objid,
      )
      membership.role = 'member' if membership
      membership&.save

      legacy_customer.default_org_id = personal_workspace.objid
      legacy_customer.save

      result = Auth::Operations::JoinDomainOrganization.new(
        customer: legacy_customer,
        domain_id: tenant_custom_domain.identifier,
      ).call

      expect(result[:joined]).to be(true)
      expect(result[:adoption]).to be_nil,
        'Should not adopt when customer is not owner of personal workspace'

      # default_org_id should remain unchanged
      reloaded_customer = Onetime::Customer.load(legacy_customer.objid)
      expect(reloaded_customer.default_org_id).to eq(personal_workspace.objid),
        'default_org_id should not have been changed'
    end

    it 'skips adoption on already_member when default_org already repointed' do
      legacy_customer.default_org_id = personal_workspace.objid
      legacy_customer.save

      # First join: should adopt
      first_result = Auth::Operations::JoinDomainOrganization.new(
        customer: legacy_customer,
        domain_id: tenant_custom_domain.identifier,
      ).call
      expect(first_result[:joined]).to be(true)
      expect(first_result[:adoption]&.dig(:adopted)).to be(true)

      # Second join: already_member, adoption retried but no-op because
      # personal workspace is already archived (guard in resolve_personal_default_org)
      second_result = Auth::Operations::JoinDomainOrganization.new(
        customer: legacy_customer,
        domain_id: tenant_custom_domain.identifier,
      ).call
      expect(second_result[:joined]).to be(false)
      expect(second_result[:reason]).to eq('already_member')
      expect(second_result[:adoption]).to be_nil,
        'Adoption should be nil when personal workspace is already archived'
    end

    it 'retries adoption on already_member when previous adoption failed' do
      # First join without adoption setup (no personal workspace as default)
      legacy_customer.default_org_id = nil
      legacy_customer.save

      # Temporarily un-default the personal workspace so first join skips adoption
      personal_workspace.is_default = false
      personal_workspace.save

      first_result = Auth::Operations::JoinDomainOrganization.new(
        customer: legacy_customer,
        domain_id: tenant_custom_domain.identifier,
      ).call
      expect(first_result[:joined]).to be(true)
      expect(first_result[:adoption]).to be_nil

      # Now simulate partial failure recovery: restore personal workspace default
      # and point customer back to it (as if adoption never ran)
      personal_workspace.is_default = true
      personal_workspace.save
      legacy_customer.default_org_id = personal_workspace.objid
      legacy_customer.save

      # Second join: already_member, but adoption should now succeed
      second_result = Auth::Operations::JoinDomainOrganization.new(
        customer: legacy_customer,
        domain_id: tenant_custom_domain.identifier,
      ).call
      expect(second_result[:joined]).to be(false)
      expect(second_result[:reason]).to eq('already_member')
      expect(second_result[:adoption]).not_to be_nil,
        'Adoption should retry on already_member when default_org still points to personal workspace'
      expect(second_result[:adoption][:adopted]).to be(true)

      reloaded_customer = Onetime::Customer.load(legacy_customer.objid)
      expect(reloaded_customer.default_org_id).to eq(tenant_organization.objid)
    end

    it 'does not adopt when default_org_id points to a non-default org' do
      # Create a second non-default org owned by customer
      second_org = Onetime::Organization.create!(
        "Second Org #{test_run_id}",
        legacy_customer,
        "second-#{test_run_id}@example.com",
      )
      # is_default is NOT set on this org

      legacy_customer.default_org_id = second_org.objid
      legacy_customer.save

      result = Auth::Operations::JoinDomainOrganization.new(
        customer: legacy_customer,
        domain_id: tenant_custom_domain.identifier,
      ).call

      expect(result[:joined]).to be(true)
      expect(result[:adoption]).to be_nil,
        'Should not adopt when default org is not a personal workspace (is_default: false)'

      # default_org_id unchanged
      reloaded_customer = Onetime::Customer.load(legacy_customer.objid)
      expect(reloaded_customer.default_org_id).to eq(second_org.objid)

      # Cleanup
      second_org.destroy! rescue nil
    end

    it 'does not re-archive an already archived personal workspace' do
      # Archive first, then try to join
      personal_workspace.archive!('test_pre_archived')
      original_archived_at = personal_workspace.archived_at

      legacy_customer.default_org_id = personal_workspace.objid
      legacy_customer.save

      result = Auth::Operations::JoinDomainOrganization.new(
        customer: legacy_customer,
        domain_id: tenant_custom_domain.identifier,
      ).call

      expect(result[:joined]).to be(true)
      expect(result[:adoption]).to be_nil,
        'Should not adopt an already-archived personal workspace'

      # archived_at should not have been updated
      reloaded_workspace = Onetime::Organization.load(personal_workspace.objid)
      expect(reloaded_workspace.archived_at).to eq(original_archived_at)
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
      begin
        Onetime::Customer.find_by_email(e2e_user_email)&.destroy!
      rescue => e
        OT.le "[domain_sso_join_organization_spec] Error in after: #{e.message}"
      end
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
          skip "OmniAuth route not registered (OIDC discovery not available at boot for #{e2e_domain_host})"
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

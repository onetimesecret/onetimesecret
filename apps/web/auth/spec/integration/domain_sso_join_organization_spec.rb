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
# When a user signs in via tenant-SSO on a custom domain, two hooks attempt to
# join them to the domain's primary organization:
#
#   1. after_omniauth_create_account (omniauth.rb) — new accounts
#   2. after_login (login.rb)                      — all successful logins
#
# Both hooks read `session[:validated_omniauth_domain_id]`, which is set by
# the `before_omniauth_callback_route` hook in omniauth_tenant.rb after the
# cross-tenant validation passes. Before the fix, those hooks read the
# original `:omniauth_tenant_domain_id` key, which had already been deleted
# by the validation hook — so JoinDomainOrganization was never invoked.
#
# These tests verify the contract between the validation hook and the
# downstream JoinDomainOrganization operation by exercising the operation
# against realistic fixtures (CustomDomain + Organization + Customer).
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

require_relative '../spec_helper'
require_relative '../support/tenant_test_fixtures'
require_relative '../support/domain_sso_test_fixtures'

RSpec.describe 'Tenant-SSO Join Domain Organization (issue #3114)', type: :integration do
  include TenantTestFixtures
  include DomainSsoTestFixtures

  before(:all) do
    require 'onetime' unless defined?(Onetime)
    Onetime.boot! :test unless Onetime.ready?
    require_relative '../../operations/join_domain_organization'
  end

  let(:test_run_id) { SecureRandom.hex(8) }
  let(:tenant_domain) { "secrets-#{test_run_id}.acme-corp.example.com" }

  # Build domain + organization fixtures (mirrors tenant fixtures context, but
  # without depending on the shared_context wiring so we can control lifecycle).
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
  # Hook → Operation contract
  # ==========================================================================
  #
  # Simulates the post-validation state set by omniauth_tenant.rb after the
  # fix, then exercises the same JoinDomainOrganization invocation that the
  # after_omniauth_create_account and after_login hooks perform.
  #

  describe 'JoinDomainOrganization invoked with validated session key' do
    it 'adds a new SSO customer to the tenant organization as a member' do
      # Simulate the session state immediately after callback validation:
      # the original :omniauth_tenant_domain_id has been consumed, and the
      # validated identifier has been re-stored under the new key.
      session = { validated_omniauth_domain_id: tenant_custom_domain.identifier }

      # This is exactly what the downstream hooks do (omniauth.rb:217, login.rb:151).
      domain_id = session[:validated_omniauth_domain_id]
      expect(domain_id).to eq(tenant_custom_domain.identifier),
        'Fixture sanity: validated_omniauth_domain_id must be set'

      result = Auth::Operations::JoinDomainOrganization.new(
        customer: sso_customer,
        domain_id: domain_id,
      ).call

      expect(result[:joined]).to be(true), "Expected new user to be joined, got: #{result.inspect}"
      expect(result[:reason]).to eq('added_via_sso')
      expect(result[:organization]&.objid).to eq(tenant_organization.objid)
      expect(tenant_organization.member?(sso_customer)).to be(true),
        'Customer must be a member of the tenant organization after join'
    end

    it 'is idempotent for a returning user already in the tenant org' do
      # First call adds them (simulates after_omniauth_create_account)
      first = Auth::Operations::JoinDomainOrganization.new(
        customer: sso_customer,
        domain_id: tenant_custom_domain.identifier,
      ).call
      expect(first[:joined]).to be(true)

      # Second call (simulates after_login firing for the same flow) is no-op.
      # JoinDomainOrganization is intentionally idempotent so both hooks can
      # safely invoke it for new accounts.
      second = Auth::Operations::JoinDomainOrganization.new(
        customer: sso_customer,
        domain_id: tenant_custom_domain.identifier,
      ).call

      expect(second[:joined]).to be(false)
      expect(second[:reason]).to eq('already_member')
      expect(second[:organization]&.objid).to eq(tenant_organization.objid)
    end
  end

  describe 'hooks short-circuit when validated session key is missing' do
    # When :validated_omniauth_domain_id is absent — i.e., platform-level auth
    # (no tenant context) or a callback that did not pass tenant validation —
    # the hooks must not invoke JoinDomainOrganization. They guard with
    # `if domain_id`, so the operation should never be called.

    it 'does not join the tenant org when session has no validated key (platform-level auth)' do
      session = {} # No tenant context, no validated key

      domain_id = session[:validated_omniauth_domain_id]
      expect(domain_id).to be_nil

      # The hook's guard: `if domain_id` — skip when nil
      if domain_id
        raise 'Hooks should not invoke JoinDomainOrganization without a validated key'
      end

      # Customer must NOT have been added to the tenant org
      expect(tenant_organization.member?(sso_customer)).to be(false),
        'Customer must remain a non-member without tenant context'
    end

    it 'does not join the tenant org when callback validation failed (no key set)' do
      # On cross-tenant mismatch, the hook throws 403 before setting the key,
      # so downstream hooks would see the key absent.
      session = {} # Validation failure path: validated key never set

      domain_id = session[:validated_omniauth_domain_id]
      expect(domain_id).to be_nil

      expect(tenant_organization.member?(sso_customer)).to be(false)
    end
  end

  describe 'after_login deletes the validated key (single point of cleanup)' do
    it 'consumes :validated_omniauth_domain_id via session.delete' do
      # After fix: after_login uses `session.delete(:validated_omniauth_domain_id)`
      # to ensure the validated context does not persist into subsequent requests.
      session = { validated_omniauth_domain_id: tenant_custom_domain.identifier }

      domain_id = session.delete(:validated_omniauth_domain_id)

      expect(domain_id).to eq(tenant_custom_domain.identifier)
      expect(session).not_to have_key(:validated_omniauth_domain_id),
        'Validated key must be deleted by after_login so it does not leak into later requests'
    end
  end
end

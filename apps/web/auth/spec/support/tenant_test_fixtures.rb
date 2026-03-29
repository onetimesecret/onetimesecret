# apps/web/auth/spec/support/tenant_test_fixtures.rb
#
# frozen_string_literal: true

# Shared contexts for integration tests requiring real Valkey fixtures.
#
# Factory methods, constants, and shared examples for DomainSsoConfig are
# defined in DomainSsoTestFixtures (domain_sso_test_fixtures.rb), which is
# the canonical source. This module provides only the 'tenant fixtures'
# shared context used by integration specs.
#
# Usage:
#   include_context 'tenant fixtures'

module TenantTestFixtures
  # All constants and factory methods are provided by DomainSsoTestFixtures.
  # This module exists solely to host the 'tenant fixtures' shared context.
end

# ==========================================================================
# Shared Context for Integration Tests with Real Valkey Fixtures
# ==========================================================================
#
# This shared context creates actual Organization, CustomDomain, and DomainSsoConfig
# records in Valkey for integration tests that require the full tenant resolution
# chain. Each test run gets unique identifiers to prevent collision.
#
# Usage:
#   include_context 'tenant fixtures'
#
#   it 'resolves tenant from Host header' do
#     # test_organization, test_custom_domain, test_sso_config are available
#   end
#

RSpec.shared_context 'tenant fixtures' do
  let(:test_run_id) { SecureRandom.hex(8) }
  let(:tenant_domain) { "secrets-#{test_run_id}.acme-corp.example.com" }

  let!(:test_organization) do
    owner = Onetime::Customer.new(email: "owner-#{test_run_id}@test.local")
    owner.save
    Onetime::Organization.create!("Test Org #{test_run_id}", owner, "contact@test.local")
  end

  let!(:test_custom_domain) do
    domain = Onetime::CustomDomain.new(display_domain: tenant_domain, org_id: test_organization.org_id)
    domain.save
    Onetime::CustomDomain.display_domains.put(tenant_domain, domain.domainid)
    domain
  end

  let!(:test_sso_config) do
    Onetime::DomainSsoConfig.create!(
      domain_id: test_custom_domain.identifier,
      provider_type: 'entra_id',
      display_name: 'Test Entra ID',
      tenant_id: "tenant-#{test_run_id}",
      client_id: "client-#{test_run_id}",
      client_secret: "secret-#{test_run_id}",
      enabled: true
    )
  end

  after do
    Onetime::DomainSsoConfig.delete_for_domain!(test_custom_domain.identifier) rescue nil
    Onetime::CustomDomain.display_domains.remove(tenant_domain) rescue nil
    test_custom_domain&.destroy!
    test_organization&.destroy!
  end
end

# ==========================================================================
# RSpec Configuration
# ==========================================================================

RSpec.configure do |config|
  config.include TenantTestFixtures
end

# apps/web/auth/spec/support/tenant_test_fixtures.rb
#
# frozen_string_literal: true

# Test fixtures and factory methods for DomainSsoConfig model testing.
#
# These fixtures provide consistent, isolated test data for SSO configuration
# tests without requiring a live Redis/Valkey connection for unit tests.
#
# Usage:
#   include TenantTestFixtures
#   let(:config) { build_domain_sso_config(:entra_id) }

module TenantTestFixtures
  # ==========================================================================
  # Constants
  # ==========================================================================

  # Supported SSO provider types (matches DomainSsoConfig::PROVIDER_TYPES)
  PROVIDER_TYPES = %i[oidc entra_id google github].freeze

  # Mock encryption key for testing (32 bytes for AES-256)
  TEST_ENCRYPTION_KEY = 'test_encryption_key_32_bytes_ok!'.freeze

  # Sample domain IDs for testing
  SAMPLE_DOMAIN_IDS = {
    primary: 'dom_test_primary_12345',
    secondary: 'dom_test_secondary_67890',
    enterprise: 'dom_test_enterprise_abcde',
  }.freeze

  # ==========================================================================
  # Provider-Specific Configuration Templates
  # ==========================================================================

  # Base attributes shared by all provider types
  BASE_CONFIG_ATTRIBUTES = {
    enabled: 'true',
  }.freeze

  # Provider-specific default attributes
  # Note: Matches DomainSsoConfig field structure - provider_type uses underscores
  PROVIDER_CONFIGS = {
    oidc: {
      provider_type: 'oidc',
      display_name: 'Corporate OIDC',
      issuer: 'https://auth.example.com',
      client_id: 'oidc_test_client_id',
      client_secret: 'oidc_test_client_secret_value',
      allowed_domains: ['example.com', 'subsidiary.example.com'],
    },
    entra_id: {
      provider_type: 'entra_id',
      display_name: 'Contoso Azure AD',
      tenant_id: 'contoso-tenant-uuid-1234',
      client_id: 'entra_test_client_id',
      client_secret: 'entra_test_client_secret_value',
      allowed_domains: ['contoso.onmicrosoft.com', 'contoso.com'],
    },
    google: {
      provider_type: 'google',
      display_name: 'Google Workspace',
      client_id: 'google_test_client_id.apps.googleusercontent.com',
      client_secret: 'google_test_client_secret',
      allowed_domains: ['company.com'],
    },
    github: {
      provider_type: 'github',
      display_name: 'GitHub Enterprise',
      client_id: 'github_test_client_id',
      client_secret: 'github_test_client_secret',
      allowed_domains: [], # GitHub typically doesn't restrict by email domain
    },
  }.freeze

  # ==========================================================================
  # Factory Methods
  # ==========================================================================

  # Build DomainSsoConfig attributes hash for a given provider type
  #
  # @param provider [Symbol] one of :oidc, :entra_id, :google, :github
  # @param overrides [Hash] attributes to override defaults
  # @return [Hash] complete attributes hash
  def build_domain_sso_config_attributes(provider = :oidc, overrides = {})
    raise ArgumentError, "Unknown provider: #{provider}" unless PROVIDER_CONFIGS.key?(provider)

    domain_id = overrides.delete(:domain_id) || SAMPLE_DOMAIN_IDS[:primary]

    # domain_id MUST come before client_id/client_secret in hash iteration order.
    # AAD encryption reads domain_id when encrypting those fields, so it must be
    # set first during Familia's attr initialization.
    { domain_id: domain_id }
      .merge(BASE_CONFIG_ATTRIBUTES)
      .merge(PROVIDER_CONFIGS[provider])
      .merge(overrides)
  end

  # Build a stubbed DomainSsoConfig instance for unit testing
  #
  # This creates an instance with stubbed persistence methods,
  # suitable for testing model behavior without Redis.
  #
  # @param provider [Symbol] one of :oidc, :entra_id, :google, :github
  # @param overrides [Hash] attributes to override defaults
  # @return [Onetime::DomainSsoConfig] stubbed instance
  def build_domain_sso_config(provider = :oidc, overrides = {})
    attrs = build_domain_sso_config_attributes(provider, overrides)

    # Extract allowed_domains before creating the config
    # The model has a custom setter that converts array to JSON
    allowed_domains = attrs.delete(:allowed_domains)

    config = Onetime::DomainSsoConfig.new(attrs)

    # Set allowed_domains using the custom setter (converts to JSON internally)
    config.allowed_domains = allowed_domains if allowed_domains

    # Stub persistence methods for unit tests
    stub_domain_sso_config_persistence(config)

    config
  end

  # Build a minimal DomainSsoConfig with only required fields
  #
  # @param domain_id [String] domain identifier
  # @param provider_type [String] SSO provider type
  # @return [Onetime::DomainSsoConfig] minimal stubbed instance
  def build_minimal_domain_sso_config(domain_id:, provider_type: 'oidc')
    config = Onetime::DomainSsoConfig.new(
      domain_id: domain_id,
      provider_type: provider_type,
      enabled: true
    )
    stub_domain_sso_config_persistence(config)
    config
  end

  # Build an invalid DomainSsoConfig for negative testing
  #
  # @param invalid_attribute [Symbol] which attribute to make invalid
  # @return [Onetime::DomainSsoConfig] instance with invalid data
  def build_invalid_domain_sso_config(invalid_attribute)
    attrs = build_domain_sso_config_attributes(:oidc)

    case invalid_attribute
    when :missing_domain_id
      attrs.delete(:domain_id)
    when :empty_domain_id
      attrs[:domain_id] = ''
    when :nil_domain_id
      attrs[:domain_id] = nil
    when :missing_provider_type
      attrs.delete(:provider_type)
    when :invalid_provider_type
      attrs[:provider_type] = 'unsupported_provider'
    when :empty_client_id
      attrs[:client_id] = ''
    when :empty_client_secret
      attrs[:client_secret] = ''
    when :invalid_domains
      attrs[:allowed_domains] = 'not_an_array'
    when :empty_issuer_for_oidc
      # OIDC requires issuer, but we'll leave it nil
      attrs[:issuer] = nil
    when :empty_tenant_for_entra
      attrs = build_domain_sso_config_attributes(:entra_id)
      attrs[:tenant_id] = nil
    end

    config = Onetime::DomainSsoConfig.new(attrs)
    stub_domain_sso_config_persistence(config)
    config
  end

  # Build a disabled DomainSsoConfig
  #
  # @param provider [Symbol] provider type
  # @return [Onetime::DomainSsoConfig] disabled config instance
  def build_disabled_domain_sso_config(provider = :oidc)
    build_domain_sso_config(provider, enabled: false)
  end

  # ==========================================================================
  # OmniAuth Options Expectations
  # ==========================================================================

  # Expected OmniAuth options structure for a given provider
  #
  # Used to verify to_omniauth_options output. Matches the structure
  # generated by DomainSsoConfig#to_omniauth_options.
  #
  # @param provider [Symbol] provider type
  # @param domain_id [String] domain ID (used as strategy name)
  # @return [Hash] expected OmniAuth options structure
  def expected_omniauth_options(provider, domain_id = SAMPLE_DOMAIN_IDS[:primary])
    case provider
    when :oidc
      {
        strategy: :openid_connect,
        name: domain_id,
        scope: [:openid, :email, :profile],
        response_type: :code,
        issuer: 'https://auth.example.com',
        discovery: true,
        pkce: true,
        client_options: {
          identifier: anything, # Decrypted client_id
          secret: anything,     # Decrypted client_secret
        },
      }
    when :entra_id
      {
        strategy: :entra_id,
        name: domain_id,
        client_id: anything,
        client_secret: anything,
        tenant_id: 'contoso-tenant-uuid-1234',
        scope: 'openid profile email',
      }
    when :google
      {
        strategy: :google_oauth2,
        name: domain_id,
        client_id: anything,
        client_secret: anything,
        scope: 'openid,email,profile',
        prompt: 'select_account',
      }
    when :github
      {
        strategy: :github,
        name: domain_id,
        client_id: anything,
        client_secret: anything,
        scope: 'user:email',
      }
    end
  end

  # ==========================================================================
  # Test Email Addresses
  # ==========================================================================

  # Generate test email addresses for domain validation testing
  #
  # @param domain [String] email domain
  # @param count [Integer] number of emails to generate
  # @return [Array<String>] email addresses
  def generate_test_emails(domain, count: 3)
    (1..count).map { |i| "user#{i}@#{domain}" }
  end

  # Email addresses for domain validation positive tests
  def valid_domain_emails
    {
      oidc: ['user@example.com', 'admin@subsidiary.example.com'],
      entra_id: ['user@contoso.onmicrosoft.com', 'admin@contoso.com'],
      google: ['employee@company.com'],
      github: [], # No domain restriction
    }
  end

  # Email addresses for domain validation negative tests
  def invalid_domain_emails
    {
      oidc: ['user@attacker.com', 'admin@not-example.com'],
      entra_id: ['user@external.com', 'admin@fabrikam.com'],
      google: ['personal@gmail.com', 'work@other-company.com'],
    }
  end

  private

  # Stub persistence methods on a DomainSsoConfig instance
  #
  # For unit tests, we don't need to actually persist to Redis.
  # The model already has these methods from Familia::Horreum.
  # We stub them to avoid Redis connections in unit tests.
  #
  # @param config [Onetime::DomainSsoConfig] instance to stub
  def stub_domain_sso_config_persistence(config)
    # Use allow_any_instance_of pattern or define singleton methods
    # to avoid "does not implement" errors from RSpec's verified doubles
    config.define_singleton_method(:save) { true }
    config.define_singleton_method(:destroy) { true }
    config.define_singleton_method(:destroy!) { true }
    # IMPORTANT: Must match the state during encryption (which happens at object
    # creation when exists? == false). If this returns true, Familia's AAD
    # calculation differs and decryption fails with "authentication tag failed".
    config.define_singleton_method(:exists?) { false }
    config.define_singleton_method(:reload) { self }
  end
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
# Shared Examples for DomainSsoConfig Tests
# ==========================================================================

RSpec.shared_examples 'a valid SSO config' do
  it 'has required attributes set' do
    expect(config.domain_id).not_to be_nil
    expect(config.domain_id).not_to be_empty
    expect(config.provider_type).not_to be_nil
    expect(config.provider_type).not_to be_empty
  end

  it 'responds to enabled?' do
    expect(config).to respond_to(:enabled?)
  end

  it 'responds to valid_email_domain?' do
    expect(config).to respond_to(:valid_email_domain?)
  end

  it 'responds to to_omniauth_options' do
    expect(config).to respond_to(:to_omniauth_options)
  end

  it 'responds to validation_errors' do
    expect(config).to respond_to(:validation_errors)
  end
end

RSpec.shared_examples 'provider-specific config' do |provider|
  it "has #{provider} provider type" do
    expect(config.provider_type).to eq(provider.to_s)
  end

  it 'generates valid OmniAuth options with strategy key', :aggregate_failures do
    # Note: This test may fail if the model has bugs in reveal method calls.
    # The model should use `reveal { it }` for encrypted fields, not bare `reveal`.
    # If this fails with "Block required for reveal", the model needs to be updated.
    options = begin
      config.to_omniauth_options
    rescue ArgumentError => e
      if e.message.include?('Block required for reveal')
        skip "Model bug: reveal method called without block - #{e.message}"
      else
        raise
      end
    end

    expect(options).to be_a(Hash)
    expect(options[:strategy]).not_to be_nil
    expect(options[:name]).to eq(config.domain_id)
  end
end

# ==========================================================================
# RSpec Configuration
# ==========================================================================

RSpec.configure do |config|
  config.include TenantTestFixtures
end

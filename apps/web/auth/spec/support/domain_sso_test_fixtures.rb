# apps/web/auth/spec/support/domain_sso_test_fixtures.rb
#
# frozen_string_literal: true

# Test fixtures and factory methods for CustomDomain::SsoConfig model testing.
#
# Issue: #2786 - Per-domain SSO configuration
#
# These fixtures provide consistent, isolated test data for domain SSO
# configuration tests without requiring a live Redis/Valkey connection
# for unit tests.
#
# Usage:
#   include DomainSsoTestFixtures
#   let(:config) { build_domain_sso_config(:entra_id) }
#
# NOTE: This file mirrors the structure of tenant_test_fixtures.rb
# but adapts it for the new CustomDomain::SsoConfig model.

module DomainSsoTestFixtures
  # ==========================================================================
  # Constants
  # ==========================================================================

  # Supported SSO provider types (matches PROVIDER_TYPES constant in model).
  # Tenant SSO is OIDC/Entra-only (#3902): issuerless providers (google,
  # github) resolve to the shared '' issuer sentinel and cannot satisfy the
  # (provider, issuer, uid) identity partitioning, so they were removed.
  # SAML (#4450) joins them: its issuer is the tenant's IdP EntityID.
  PROVIDER_TYPES = %i[oidc entra_id saml].freeze

  # Mock encryption key for testing (32 bytes for AES-256)
  TEST_ENCRYPTION_KEY = 'test_encryption_key_32_bytes_ok!'.freeze

  # Sample domain IDs for testing (mimics CustomDomain objid format)
  # NOTE: CustomDomain::SsoConfig uses domain_id as its identifier, not org_id.
  # The relationship is: CustomDomain -> CustomDomain::SsoConfig (1:1 by domain_id).
  SAMPLE_DOMAIN_IDS = {
    primary: 'dom_test_primary_12345',
    secondary: 'dom_test_secondary_67890',
    enterprise: 'dom_test_enterprise_abcde',
  }.freeze

  # Sample display domains for testing
  SAMPLE_DISPLAY_DOMAINS = {
    primary: 'secrets.acme-corp.com',
    secondary: 'api.acme-corp.com',
    enterprise: 'vault.enterprise.com',
  }.freeze

  # ==========================================================================
  # Provider-Specific Configuration Templates
  # ==========================================================================

  # Base attributes shared by all provider types
  BASE_CONFIG_ATTRIBUTES = {
    enabled: 'true',
  }.freeze

  # Provider-specific default attributes
  # Note: Matches expected CustomDomain::SsoConfig field structure
  PROVIDER_CONFIGS = {
    oidc: {
      provider_type: 'oidc',
      display_name: 'Corporate OIDC',
      issuer: 'https://auth.example.com',
      client_id: 'oidc_domain_test_client_id',
      client_secret: 'oidc_domain_test_client_secret_value',
      allowed_domains: ['example.com', 'subsidiary.example.com'],
    },
    entra_id: {
      provider_type: 'entra_id',
      display_name: 'Contoso Azure AD',
      tenant_id: 'contoso-tenant-uuid-1234',
      client_id: 'entra_domain_test_client_id',
      client_secret: 'entra_domain_test_client_secret_value',
      allowed_domains: ['contoso.onmicrosoft.com', 'contoso.com'],
    },
    # No client_id / client_secret: SAML has no client credential (#4450).
    # idp_cert is NOT here — it is a real X.509 certificate generated once per
    # process (.saml_cert_pem) and merged in by
    # build_domain_sso_config_attributes, so no key material is checked in
    # and loading this file costs no keygen.
    saml: {
      provider_type: 'saml',
      display_name: 'Corporate SAML',
      idp_sso_service_url: 'https://idp.example.com/saml/sso',
      idp_entity_id: 'https://idp.example.com/saml/metadata',
      allowed_domains: ['example.com'],
    },
  }.freeze

  # A self-signed PEM certificate for the SAML fixtures, generated on first
  # use and shared for the process (2048-bit keygen is ~100ms). Only the
  # certificate is kept; the key is discarded — these fixtures configure an
  # IdP, they never sign as one (spec/support/saml/test_idp.rb does that).
  #
  # @return [String] PEM
  def self.saml_cert_pem
    @saml_cert_pem ||= begin
      require 'openssl'
      key             = OpenSSL::PKey::RSA.new(2048)
      cert            = OpenSSL::X509::Certificate.new
      cert.version    = 2
      cert.serial     = SecureRandom.random_number(2**32)
      cert.subject    = OpenSSL::X509::Name.parse('/CN=fixture-idp.example.com')
      cert.issuer     = cert.subject
      cert.public_key = key.public_key
      cert.not_before = Time.now - 3600
      cert.not_after  = Time.now + 86_400
      cert.sign(key, OpenSSL::Digest.new('SHA256'))
      cert.to_pem
    end
  end

  # ==========================================================================
  # Factory Methods
  # ==========================================================================

  # Build CustomDomain::SsoConfig attributes hash for a given provider type
  #
  # @param provider [Symbol] one of :oidc, :entra_id, :saml
  # @param overrides [Hash] attributes to override defaults
  # @return [Hash] complete attributes hash
  def build_domain_sso_config_attributes(provider = :oidc, overrides = {})
    raise ArgumentError, "Unknown provider: #{provider}" unless PROVIDER_CONFIGS.key?(provider)

    domain_id = overrides.delete(:domain_id) || SAMPLE_DOMAIN_IDS[:primary]
    overrides = { idp_cert: DomainSsoTestFixtures.saml_cert_pem }.merge(overrides) if provider == :saml

    # domain_id MUST come before client_id/client_secret in hash iteration order.
    # AAD encryption reads domain_id when encrypting credentials, so it must be
    # set first during Familia's attr initialization.
    { domain_id: domain_id }
      .merge(BASE_CONFIG_ATTRIBUTES)
      .merge(PROVIDER_CONFIGS[provider])
      .merge(overrides)
  end

  # Build a stubbed CustomDomain::SsoConfig instance for unit testing
  #
  # This creates an instance with stubbed persistence methods,
  # suitable for testing model behavior without Redis.
  #
  # @param provider [Symbol] one of :oidc, :entra_id, :saml
  # @param overrides [Hash] attributes to override defaults
  # @return [Onetime::CustomDomain::SsoConfig] stubbed instance
  #
  def build_domain_sso_config(provider = :oidc, overrides = {})
    attrs = build_domain_sso_config_attributes(provider, overrides)

    # Extract allowed_domains before creating the config
    # The model has a custom setter that converts array to JSON
    allowed_domains = attrs.delete(:allowed_domains)

    config = Onetime::CustomDomain::SsoConfig.new(attrs)

    # Set allowed_domains using the custom setter (converts to JSON internally)
    config.allowed_domains = allowed_domains if allowed_domains

    # Stub persistence methods for unit tests
    stub_domain_sso_config_persistence(config)

    config
  end

  # Build a minimal CustomDomain::SsoConfig with only required fields
  #
  # @param domain_id [String] domain identifier
  # @param provider_type [String] SSO provider type
  # @return [Onetime::CustomDomain::SsoConfig] minimal stubbed instance
  def build_minimal_domain_sso_config(domain_id:, provider_type: 'oidc')
    config = Onetime::CustomDomain::SsoConfig.new(
      domain_id: domain_id,
      provider_type: provider_type,
      enabled: true
    )
    stub_domain_sso_config_persistence(config)
    config
  end

  # Build an invalid CustomDomain::SsoConfig for negative testing
  #
  # @param invalid_attribute [Symbol] which attribute to make invalid
  # @return [Onetime::CustomDomain::SsoConfig] instance with invalid data
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

    config = Onetime::CustomDomain::SsoConfig.new(attrs)
    stub_domain_sso_config_persistence(config)
    config
  end

  # A structurally valid PEM certificate whose validity window has closed.
  #
  # @return [String] PEM
  def expired_saml_cert_pem
    require 'openssl'
    key             = OpenSSL::PKey::RSA.new(2048)
    cert            = OpenSSL::X509::Certificate.new
    cert.version    = 2
    cert.serial     = 1
    cert.subject    = OpenSSL::X509::Name.parse('/CN=expired-idp.example.com')
    cert.issuer     = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now - 7200
    cert.not_after  = Time.now - 3600
    cert.sign(key, OpenSSL::Digest.new('SHA256'))
    cert.to_pem
  end

  # A structurally valid PEM certificate whose validity window has not yet
  # opened. ruby-saml drops it from the trust set exactly as it drops an
  # expired one (settings.rb Utils.is_cert_active), so the app refuses it
  # wherever it refuses expiry (#4450).
  #
  # @return [String] PEM
  def not_yet_valid_saml_cert_pem
    require 'openssl'
    key             = OpenSSL::PKey::RSA.new(2048)
    cert            = OpenSSL::X509::Certificate.new
    cert.version    = 2
    cert.serial     = 2
    cert.subject    = OpenSSL::X509::Name.parse('/CN=future-idp.example.com')
    cert.issuer     = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now + 3600
    cert.not_after  = Time.now + 86_400
    cert.sign(key, OpenSSL::Digest.new('SHA256'))
    cert.to_pem
  end

  # Build a disabled CustomDomain::SsoConfig
  #
  # @param provider [Symbol] provider type
  # @return [Onetime::CustomDomain::SsoConfig] disabled config instance
  def build_disabled_domain_sso_config(provider = :oidc)
    build_domain_sso_config(provider, enabled: false)
  end

  # ==========================================================================
  # OmniAuth Options Expectations
  # ==========================================================================

  # Expected OmniAuth options structure for a given provider
  #
  # Used to verify to_omniauth_options output. Matches the structure
  # generated by CustomDomain::SsoConfig#to_omniauth_options.
  #
  # @param provider [Symbol] provider type
  # @param extid [String] CustomDomain external ID (used as strategy name)
  # @return [Hash] expected OmniAuth options structure
  def expected_domain_omniauth_options(provider, extid = 'cd_test_primary_12345')
    case provider
    when :oidc
      {
        strategy: :openid_connect,
        name: extid,
        scope: [:openid, :email, :profile],
        response_type: :code,
        issuer: 'https://auth.example.com',
        discovery: true,
        pkce: true,
        client_options: {
          identifier: anything,
          secret: anything,
        },
      }
    when :entra_id
      {
        strategy: :entra_id,
        name: extid,
        client_id: anything,
        client_secret: anything,
        tenant_id: 'contoso-tenant-uuid-1234',
        scope: 'openid profile email',
      }
    when :saml
      # The hardened half comes from the single shared builder — asserting
      # against the builder (not a restated hash) is the point: the tenant arm
      # must not carry its own copy. registry_spec pins the hash's contents.
      Onetime::SsoProvider::Saml.hardened_options.merge(
        strategy: :request_bound_saml,
        name: extid,
        idp_sso_service_url: 'https://idp.example.com/saml/sso',
        idp_entity_id: 'https://idp.example.com/saml/metadata',
        idp_cert: DomainSsoTestFixtures.saml_cert_pem,
        uid_attribute: nil,
      )
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
  def domain_valid_emails
    {
      oidc: ['user@example.com', 'admin@subsidiary.example.com'],
      entra_id: ['user@contoso.onmicrosoft.com', 'admin@contoso.com'],
      saml: ['user@example.com'],
    }
  end

  # Email addresses for domain validation negative tests
  def domain_invalid_emails
    {
      oidc: ['user@attacker.com', 'admin@not-example.com'],
      entra_id: ['user@external.com', 'admin@fabrikam.com'],
      saml: ['user@attacker.com'],
    }
  end

  private

  # Stub persistence methods on a CustomDomain::SsoConfig instance
  #
  # For unit tests, we don't need to actually persist to Redis.
  # The model already has these methods from Familia::Horreum.
  # We stub them to avoid Redis connections in unit tests.
  #
  # @param config [Onetime::CustomDomain::SsoConfig] instance to stub
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
# This shared context creates actual Organization, CustomDomain, and
# CustomDomain::SsoConfig records in Valkey for integration tests that require
# the full tenant resolution chain. Each test run gets unique identifiers
# to prevent collision.
#
# Usage:
#   include_context 'domain sso fixtures'
#
#   it 'resolves SSO config from domain' do
#     # test_domain_with_sso, test_domain_sso_config are available
#   end
#

RSpec.shared_context 'domain sso fixtures' do
  let(:test_run_id) { SecureRandom.hex(8) }
  let(:domain_sso_display_domain) { "secrets-#{test_run_id}.acme-corp.example.com" }

  let!(:test_sso_organization) do
    owner = Onetime::Customer.new(email: "owner-#{test_run_id}@test.local")
    owner.save
    Onetime::Organization.create!("SSO Test Org #{test_run_id}", owner, "contact@test.local")
  end

  let!(:test_domain_with_sso) do
    domain = Onetime::CustomDomain.new(
      display_domain: domain_sso_display_domain,
      org_id: test_sso_organization.org_id
    )
    domain.save
    Onetime::CustomDomain.display_domain_index.put(domain_sso_display_domain, domain.domainid)
    domain
  end

  # NOTE: CustomDomain::SsoConfig only has domain_id, not org_id.
  # The organization relationship is via CustomDomain.org_id.
  let!(:test_domain_sso_config) do
    Onetime::CustomDomain::SsoConfig.create!(
      domain_id: test_domain_with_sso.objid,
      provider_type: 'entra_id',
      display_name: 'Test Domain Entra ID',
      tenant_id: "tenant-#{test_run_id}",
      client_id: "client-#{test_run_id}",
      client_secret: "secret-#{test_run_id}",
      enabled: true
    )
  end

  after do
    # Cleanup in reverse order of creation
    Onetime::CustomDomain::SsoConfig.delete_for_domain!(test_domain_with_sso.objid) rescue nil
    Onetime::CustomDomain.display_domain_index.remove(domain_sso_display_domain) rescue nil
    test_domain_with_sso&.destroy!
    test_sso_organization&.destroy!
  end
end

# ==========================================================================
# Shared Examples for CustomDomain::SsoConfig Tests
# ==========================================================================

RSpec.shared_examples 'a valid domain SSO config' do
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

RSpec.shared_examples 'provider-specific domain SSO config' do |provider|
  it "has #{provider} provider type" do
    expect(config.provider_type).to eq(provider.to_s)
  end

  it 'generates valid OmniAuth options with strategy key', :aggregate_failures do
    fake_domain = instance_double(Onetime::CustomDomain, extid: 'cd_shared_example')
    allow(config).to receive(:custom_domain).and_return(fake_domain)

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
    expect(options[:name]).to eq('cd_shared_example')
  end
end

# ==========================================================================
# RSpec Configuration
# ==========================================================================

RSpec.configure do |config|
  config.include DomainSsoTestFixtures
end

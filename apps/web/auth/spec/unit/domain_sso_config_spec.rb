# apps/web/auth/spec/unit/domain_sso_config_spec.rb
#
# frozen_string_literal: true

# Unit tests for CustomDomain::SsoConfig model (per-domain SSO configuration)
#
# Issue: #2786 - Per-domain SSO configuration
#
# Tests cover:
# - Model CRUD operations
# - Client secret encryption/decryption with domain_id binding
# - to_omniauth_options generation for different providers
# - enabled? flag behavior
# - valid_email_domain? validation against allowed_domains
# - configs_by_domain class hashkey for O(1) lookup
# - Domain ownership validation
#
# These are unit tests - they don't require Valkey/Redis.
# Integration tests for persistence belong in a separate file.
#
# Run:
#   pnpm run test:rspec apps/web/auth/spec/unit/domain_sso_config_spec.rb

require_relative '../spec_helper'
require_relative '../support/domain_sso_test_fixtures'

RSpec.describe Onetime::CustomDomain::SsoConfig do
  include DomainSsoTestFixtures

  # Configure Familia encryption for testing, saving originals for restoration
  # CustomDomain::SsoConfig uses encrypted_field which requires key configuration
  # Keys must be Base64-encoded 32-byte values
  before(:all) do
    @original_encryption_keys = Familia.config.encryption_keys&.dup
    @original_key_version = Familia.config.current_key_version
    @original_personalization = Familia.config.encryption_personalization

    # Generate valid 32-byte keys and Base64 encode them
    key_v1 = 'test_encryption_key_32bytes_ok!!' # Exactly 32 bytes
    key_v2 = 'another_test_key_for_testing_!!' # Exactly 32 bytes

    Familia.configure do |config|
      config.encryption_keys = {
        v1: Base64.strict_encode64(key_v1),
        v2: Base64.strict_encode64(key_v2),
      }
      config.current_key_version = :v1
      config.encryption_personalization = 'CustomDomain::SsoConfigTest'
    end
  end

  # Restore original Familia encryption config to avoid cross-contamination
  after(:all) do
    Familia.configure do |config|
      config.encryption_keys = @original_encryption_keys if @original_encryption_keys
      config.current_key_version = @original_key_version if @original_key_version
      config.encryption_personalization = @original_personalization if @original_personalization
    end
  end

  # ==========================================================================
  # Model Interface Tests
  # ==========================================================================

  describe 'model interface' do
    let(:config) { build_domain_sso_config(:oidc) }

    describe 'expected methods' do
      it 'responds to domain_id (identifier field)' do
        expect(config).to respond_to(:domain_id)
      end

      it 'responds to provider_type' do
        expect(config).to respond_to(:provider_type)
      end

      it 'responds to enabled and enabled?' do
        expect(config).to respond_to(:enabled)
        expect(config).to respond_to(:enabled?)
      end

      it 'responds to client_id (encrypted)' do
        expect(config).to respond_to(:client_id)
      end

      it 'responds to client_secret (encrypted)' do
        expect(config).to respond_to(:client_secret)
      end

      it 'responds to allowed_domains' do
        expect(config).to respond_to(:allowed_domains)
      end

      it 'responds to to_omniauth_options' do
        expect(config).to respond_to(:to_omniauth_options)
      end

      it 'responds to valid_email_domain?' do
        expect(config).to respond_to(:valid_email_domain?)
      end

      it 'responds to validation_errors' do
        expect(config).to respond_to(:validation_errors)
      end

      it 'responds to valid?' do
        expect(config).to respond_to(:valid?)
      end

      it 'responds to custom_domain (association)' do
        expect(config).to respond_to(:custom_domain)
      end

      it 'responds to organization (association)' do
        expect(config).to respond_to(:organization)
      end
    end
  end

  # ==========================================================================
  # Identifier and Key Structure Tests
  # ==========================================================================

  describe 'identifier and key structure' do
    it 'uses domain_id as identifier field' do
      config = build_domain_sso_config(:oidc)
      expect(config.identifier).to eq(config.domain_id)
    end

    it 'uses custom_domain__sso_config prefix in class configuration' do
      # Verify the class is configured with the correct prefix
      # The actual Redis key is constructed internally by Familia
      expect(Onetime::CustomDomain::SsoConfig.prefix).to eq(:custom_domain__sso_config)
    end
  end

  # ==========================================================================
  # Config Creation Tests
  # ==========================================================================

  describe 'config creation' do
    describe 'with valid OIDC attributes' do
      it 'stores domain_id' do
        config = build_domain_sso_config(:oidc, domain_id: 'dom_test_123')
        expect(config.domain_id).to eq('dom_test_123')
      end

      it 'stores provider type' do
        config = build_domain_sso_config(:oidc)
        expect(config.provider_type).to eq('oidc')
      end

      it 'stores issuer' do
        config = build_domain_sso_config(:oidc)
        expect(config.issuer).to eq('https://auth.example.com')
      end
    end

    describe 'with valid Entra ID attributes' do
      it 'stores tenant_id' do
        config = build_domain_sso_config(:entra_id)
        expect(config.tenant_id).to eq('contoso-tenant-uuid-1234')
      end
    end
  end

  # ==========================================================================
  # Client Secret Encryption Tests
  # ==========================================================================

  describe 'client_secret encryption' do
    let(:plaintext_secret) { 'super_secret_client_secret_value' }

    context 'when setting client_secret' do
      it 'accepts a plaintext value' do
        config = build_domain_sso_config(:oidc)
        expect { config.client_secret = plaintext_secret }.not_to raise_error
      end
    end

    context 'when retrieving client_secret' do
      it 'returns ConcealedString that can be revealed' do
        config = build_domain_sso_config(:oidc)
        config.client_secret = plaintext_secret
        expect(config.client_secret.reveal { it }).to eq(plaintext_secret)
      end

      it 'conceals the value in string representation' do
        config = build_domain_sso_config(:oidc)
        config.client_secret = plaintext_secret
        expect(config.client_secret.to_s).to eq('[CONCEALED]')
      end
    end
  end

  # ==========================================================================
  # to_omniauth_options Tests
  # ==========================================================================

  describe '#to_omniauth_options' do
    describe 'for OIDC provider' do
      let(:config) { build_domain_sso_config(:oidc) }

      it 'returns a Hash' do
        expect(config.to_omniauth_options).to be_a(Hash)
      end

      it 'specifies :openid_connect strategy' do
        expect(config.to_omniauth_options[:strategy]).to eq(:openid_connect)
      end

      it 'uses domain_id as the strategy name' do
        expect(config.to_omniauth_options[:name]).to eq(config.domain_id)
      end

      it 'includes issuer' do
        expect(config.to_omniauth_options[:issuer]).to eq('https://auth.example.com')
      end

      it 'enables discovery' do
        expect(config.to_omniauth_options[:discovery]).to be true
      end

      it 'enables PKCE' do
        expect(config.to_omniauth_options[:pkce]).to be true
      end
    end

    describe 'for Entra ID provider' do
      let(:config) { build_domain_sso_config(:entra_id) }

      it 'specifies :entra_id strategy' do
        expect(config.to_omniauth_options[:strategy]).to eq(:entra_id)
      end

      it 'includes tenant_id' do
        expect(config.to_omniauth_options[:tenant_id]).to eq('contoso-tenant-uuid-1234')
      end
    end

    describe 'for Google provider' do
      let(:config) { build_domain_sso_config(:google) }

      it 'specifies :google_oauth2 strategy' do
        expect(config.to_omniauth_options[:strategy]).to eq(:google_oauth2)
      end
    end

    describe 'for GitHub provider' do
      let(:config) { build_domain_sso_config(:github) }

      it 'specifies :github strategy' do
        expect(config.to_omniauth_options[:strategy]).to eq(:github)
      end
    end
  end

  # ==========================================================================
  # enabled? Tests
  # ==========================================================================

  describe '#enabled?' do
    context 'when enabled is true' do
      it 'returns true' do
        config = build_domain_sso_config(:oidc, enabled: 'true')
        expect(config.enabled?).to be true
      end
    end

    context 'when enabled is false' do
      it 'returns false' do
        config = build_domain_sso_config(:oidc, enabled: 'false')
        expect(config.enabled?).to be false
      end
    end

    context 'when enabled is nil' do
      it 'returns false (nil treated as disabled)' do
        config = build_domain_sso_config(:oidc)
        config.enabled = nil
        expect(config.enabled?).to be false
      end
    end
  end

  # ==========================================================================
  # valid_email_domain? Tests
  # ==========================================================================

  describe '#valid_email_domain?' do
    describe 'with domain restrictions' do
      let(:config) { build_domain_sso_config(:oidc) }

      it 'returns true for matching domain' do
        expect(config.valid_email_domain?('user@example.com')).to be true
      end

      it 'returns false for non-matching domain' do
        expect(config.valid_email_domain?('user@attacker.com')).to be false
      end

      it 'is case-insensitive' do
        expect(config.valid_email_domain?('user@EXAMPLE.COM')).to be true
      end
    end

    describe 'without domain restrictions' do
      let(:config) { build_domain_sso_config(:github) }

      it 'allows any email domain' do
        expect(config.valid_email_domain?('user@anydomain.com')).to be true
      end
    end
  end

  # ==========================================================================
  # Finder Method Tests
  # ==========================================================================

  describe '.find_by_domain_id' do
    it 'responds to find_by_domain_id' do
      expect(described_class).to respond_to(:find_by_domain_id)
    end

    it 'returns nil for empty domain_id' do
      expect(described_class.find_by_domain_id('')).to be_nil
      expect(described_class.find_by_domain_id(nil)).to be_nil
    end
  end

  describe '.exists_for_domain?' do
    it 'responds to exists_for_domain?' do
      expect(described_class).to respond_to(:exists_for_domain?)
    end

    it 'returns false for empty domain_id' do
      expect(described_class.exists_for_domain?('')).to be false
    end
  end

  # ==========================================================================
  # Create and Delete Tests
  # ==========================================================================

  describe '.create!' do
    it 'responds to create!' do
      expect(described_class).to respond_to(:create!)
    end

    it 'raises error if domain_id is empty' do
      expect { described_class.create!(domain_id: '') }
        .to raise_error(Onetime::Problem, /domain_id is required/)
    end
  end

  describe '.delete_for_domain!' do
    it 'responds to delete_for_domain!' do
      expect(described_class).to respond_to(:delete_for_domain!)
    end

    it 'returns false for empty domain_id' do
      expect(described_class.delete_for_domain!('')).to be false
    end
  end

  # ==========================================================================
  # PROVIDER_METADATA Tests
  # ==========================================================================

  describe 'PROVIDER_METADATA constant' do
    it 'defines metadata for all provider types' do
      expect(described_class::PROVIDER_METADATA).to be_a(Hash)
      expect(described_class::PROVIDER_METADATA.keys).to include('oidc', 'entra_id', 'google', 'github')
    end
  end

  describe '#requires_domain_filter?' do
    it 'returns true for GitHub' do
      config = build_domain_sso_config(:github)
      expect(config.requires_domain_filter?).to be true
    end

    it 'returns false for Entra ID' do
      config = build_domain_sso_config(:entra_id)
      expect(config.requires_domain_filter?).to be false
    end
  end

  # ==========================================================================
  # Enable/Disable Tests
  # ==========================================================================

  describe '#enable!' do
    it 'responds to enable!' do
      config = build_domain_sso_config(:oidc)
      expect(config).to respond_to(:enable!)
    end
  end

  describe '#disable!' do
    it 'responds to disable!' do
      config = build_domain_sso_config(:oidc)
      expect(config).to respond_to(:disable!)
    end
  end

  # ==========================================================================
  # AAD Encryption Isolation Tests
  # ==========================================================================
  #
  # These tests verify that encrypted_field with aad_fields: [:domain_id]
  # produces domain-bound ciphertext. The AAD (Additional Authenticated Data)
  # binds credentials to a specific domain_id, preventing cross-domain
  # credential swapping even if an attacker has direct database access.
  #
  # Encryption context for unsaved records (exists? == false):
  #   AAD = "Onetime::CustomDomain::SsoConfig:<field_name>:<domain_id>"
  #
  # Changing the domain_id changes both the encryption context string and
  # the derived key, so decryption under a different domain_id fails with
  # an authentication tag mismatch.

  describe 'AAD encryption isolation' do
    let(:domain_a_id) { 'dom_aad_test_domain_a' }
    let(:domain_b_id) { 'dom_aad_test_domain_b' }
    let(:plaintext_client_id) { 'my-oauth-client-id-12345' }
    let(:plaintext_client_secret) { 'super-secret-value-for-aad-test' }

    describe 'client_id encryption with domain_id binding' do
      it 'produces non-nil ciphertext when encrypted with a domain_id' do
        config = build_domain_sso_config(:oidc, domain_id: domain_a_id)
        config.client_id = plaintext_client_id

        encrypted_json = config.client_id.encrypted_value
        expect(encrypted_json).not_to be_nil
        expect(encrypted_json).not_to eq(plaintext_client_id)
      end

      it 'decrypts successfully with the same domain_id' do
        config = build_domain_sso_config(:oidc, domain_id: domain_a_id)
        config.client_id = plaintext_client_id

        revealed = config.client_id.reveal { it }
        expect(revealed).to eq(plaintext_client_id)
      end

      it 'fails to decrypt when the encrypted value is moved to a config with a different domain_id' do
        # Encrypt under domain A
        config_a = build_domain_sso_config(:oidc, domain_id: domain_a_id)
        config_a.client_id = plaintext_client_id
        stolen_ciphertext = config_a.client_id.encrypted_value

        # Build config B with a different domain_id and inject the stolen ciphertext
        config_b = build_domain_sso_config(:oidc, domain_id: domain_b_id)
        # Bypass the normal setter by injecting the raw encrypted JSON
        # The setter recognizes encrypted JSON and wraps it without re-encrypting
        config_b.client_id = stolen_ciphertext

        # Attempting to reveal should fail because the decryption context
        # (domain_id) no longer matches what was used during encryption
        expect {
          config_b.client_id.reveal { it }
        }.to raise_error(Familia::EncryptionError)
      end
    end

    describe 'client_secret encryption with domain_id binding' do
      it 'produces non-nil ciphertext when encrypted with a domain_id' do
        config = build_domain_sso_config(:oidc, domain_id: domain_a_id)
        config.client_secret = plaintext_client_secret

        encrypted_json = config.client_secret.encrypted_value
        expect(encrypted_json).not_to be_nil
        expect(encrypted_json).not_to eq(plaintext_client_secret)
      end

      it 'decrypts successfully with the same domain_id' do
        config = build_domain_sso_config(:oidc, domain_id: domain_a_id)
        config.client_secret = plaintext_client_secret

        revealed = config.client_secret.reveal { it }
        expect(revealed).to eq(plaintext_client_secret)
      end

      it 'fails to decrypt when the encrypted value is moved to a config with a different domain_id' do
        # Encrypt under domain A
        config_a = build_domain_sso_config(:oidc, domain_id: domain_a_id)
        config_a.client_secret = plaintext_client_secret
        stolen_ciphertext = config_a.client_secret.encrypted_value

        # Build config B with a different domain_id and inject the stolen ciphertext
        config_b = build_domain_sso_config(:oidc, domain_id: domain_b_id)
        config_b.client_secret = stolen_ciphertext

        expect {
          config_b.client_secret.reveal { it }
        }.to raise_error(Familia::EncryptionError)
      end
    end

    describe 'cross-field isolation' do
      it 'produces different ciphertext for client_id and client_secret with the same plaintext' do
        config = build_domain_sso_config(:oidc, domain_id: domain_a_id)
        same_value = 'identical-plaintext-value'
        config.client_id = same_value
        config.client_secret = same_value

        # Even with the same plaintext and domain_id, the encryption context
        # includes the field name, so ciphertext should differ
        ciphertext_id = config.client_id.encrypted_value
        ciphertext_secret = config.client_secret.encrypted_value
        expect(ciphertext_id).not_to eq(ciphertext_secret)
      end
    end
  end

  # ==========================================================================
  # validation_errors Direct Tests
  # ==========================================================================
  #
  # These tests exercise the validation_errors method directly rather than
  # relying on it being tested indirectly through other code paths.
  # The method returns an array of human-readable error strings.

  describe '#validation_errors' do
    context 'with a fully valid OIDC config' do
      let(:config) { build_domain_sso_config(:oidc) }

      it 'returns an empty errors array' do
        expect(config.validation_errors).to eq([])
      end
    end

    context 'with a fully valid Entra ID config' do
      let(:config) { build_domain_sso_config(:entra_id) }

      it 'returns an empty errors array' do
        expect(config.validation_errors).to eq([])
      end
    end

    context 'with a fully valid Google config' do
      let(:config) { build_domain_sso_config(:google) }

      it 'returns an empty errors array' do
        expect(config.validation_errors).to eq([])
      end
    end

    context 'with a fully valid GitHub config' do
      let(:config) { build_domain_sso_config(:github) }

      it 'returns an empty errors array' do
        expect(config.validation_errors).to eq([])
      end
    end

    context 'when provider_type is missing' do
      it 'returns an error about provider_type' do
        config = build_domain_sso_config(:oidc)
        config.provider_type = nil

        errors = config.validation_errors
        expect(errors).to include('provider_type is required')
      end
    end

    context 'when provider_type is empty string' do
      it 'returns an error about provider_type' do
        config = build_domain_sso_config(:oidc)
        config.provider_type = ''

        errors = config.validation_errors
        expect(errors).to include('provider_type is required')
      end
    end

    context 'when provider_type is invalid' do
      it 'returns an error about valid provider types' do
        config = build_domain_sso_config(:oidc)
        config.provider_type = 'unsupported_provider'

        errors = config.validation_errors
        expect(errors).to include(
          "provider_type must be one of: #{Onetime::CustomDomain::SsoConfig::PROVIDER_TYPES.join(', ')}"
        )
      end
    end

    context 'when client_id is missing' do
      it 'returns an error about client_id' do
        config = build_domain_sso_config(:oidc)
        config.client_id = nil

        errors = config.validation_errors
        expect(errors).to include('client_id is required')
      end
    end

    context 'when client_id is empty string' do
      it 'returns an error about client_id' do
        config = build_domain_sso_config(:oidc)
        config.client_id = ''

        errors = config.validation_errors
        expect(errors).to include('client_id is required')
      end
    end

    context 'when client_secret is missing' do
      it 'returns an error about client_secret' do
        config = build_domain_sso_config(:oidc)
        config.client_secret = nil

        errors = config.validation_errors
        expect(errors).to include('client_secret is required')
      end
    end

    context 'when client_secret is empty string' do
      it 'returns an error about client_secret' do
        config = build_domain_sso_config(:oidc)
        config.client_secret = ''

        errors = config.validation_errors
        expect(errors).to include('client_secret is required')
      end
    end

    context 'when domain_id is missing' do
      it 'returns an error about domain_id' do
        config = build_domain_sso_config(:oidc, domain_id: '')

        errors = config.validation_errors
        expect(errors).to include('domain_id is required')
      end
    end

    # Provider-specific required fields

    context 'when Entra ID config is missing tenant_id' do
      it 'returns an error about tenant_id' do
        config = build_domain_sso_config(:entra_id)
        config.tenant_id = nil

        errors = config.validation_errors
        expect(errors).to include('tenant_id is required for Entra ID provider')
      end
    end

    context 'when Entra ID config has empty tenant_id' do
      it 'returns an error about tenant_id' do
        config = build_domain_sso_config(:entra_id)
        config.tenant_id = ''

        errors = config.validation_errors
        expect(errors).to include('tenant_id is required for Entra ID provider')
      end
    end

    context 'when OIDC config is missing issuer' do
      it 'returns an error about issuer' do
        config = build_domain_sso_config(:oidc)
        config.issuer = nil

        errors = config.validation_errors
        expect(errors).to include('issuer is required for OIDC provider')
      end
    end

    context 'when OIDC config has empty issuer' do
      it 'returns an error about issuer' do
        config = build_domain_sso_config(:oidc)
        config.issuer = ''

        errors = config.validation_errors
        expect(errors).to include('issuer is required for OIDC provider')
      end
    end

    # Google and GitHub should NOT require tenant_id or issuer

    context 'when Google config has no tenant_id or issuer' do
      it 'does not return provider-specific field errors' do
        config = build_domain_sso_config(:google)
        errors = config.validation_errors
        expect(errors).not_to include(a_string_matching(/tenant_id/))
        expect(errors).not_to include(a_string_matching(/issuer/))
      end
    end

    context 'when GitHub config has no tenant_id or issuer' do
      it 'does not return provider-specific field errors' do
        config = build_domain_sso_config(:github)
        errors = config.validation_errors
        expect(errors).not_to include(a_string_matching(/tenant_id/))
        expect(errors).not_to include(a_string_matching(/issuer/))
      end
    end

    # Multiple errors at once

    context 'when multiple fields are missing' do
      it 'returns all applicable errors' do
        config = build_domain_sso_config(:oidc, domain_id: '')
        config.provider_type = nil
        config.client_id = nil
        config.client_secret = nil

        errors = config.validation_errors
        expect(errors).to include('domain_id is required')
        expect(errors).to include('provider_type is required')
        expect(errors).to include('client_id is required')
        expect(errors).to include('client_secret is required')
        expect(errors.length).to be >= 4
      end
    end
  end

  # ==========================================================================
  # valid? Direct Tests
  # ==========================================================================

  describe '#valid?' do
    context 'when validation_errors is empty' do
      it 'returns true' do
        config = build_domain_sso_config(:oidc)
        expect(config.validation_errors).to be_empty
        expect(config.valid?).to be true
      end
    end

    context 'when validation_errors is non-empty' do
      it 'returns false for missing provider_type' do
        config = build_domain_sso_config(:oidc)
        config.provider_type = nil
        expect(config.valid?).to be false
      end

      it 'returns false for missing client_id' do
        config = build_domain_sso_config(:oidc)
        config.client_id = nil
        expect(config.valid?).to be false
      end

      it 'returns false for invalid provider_type' do
        config = build_domain_sso_config(:oidc)
        config.provider_type = 'bogus'
        expect(config.valid?).to be false
      end
    end
  end
end

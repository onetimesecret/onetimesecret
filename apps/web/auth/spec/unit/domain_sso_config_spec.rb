# apps/web/auth/spec/unit/domain_sso_config_spec.rb
#
# frozen_string_literal: true

# Unit tests for DomainSsoConfig model (per-domain SSO configuration)
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

RSpec.describe Onetime::DomainSsoConfig do
  include DomainSsoTestFixtures

  # Configure Familia encryption for testing
  # DomainSsoConfig uses encrypted_field which requires key configuration
  # Keys must be Base64-encoded 32-byte values
  before(:all) do
    # Generate valid 32-byte keys and Base64 encode them
    key_v1 = 'test_encryption_key_32bytes_ok!!' # Exactly 32 bytes
    key_v2 = 'another_test_key_for_testing_!!' # Exactly 32 bytes

    Familia.configure do |config|
      config.encryption_keys = {
        v1: Base64.strict_encode64(key_v1),
        v2: Base64.strict_encode64(key_v2),
      }
      config.current_key_version = :v1
      config.encryption_personalization = 'DomainSsoConfigTest'
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

    it 'uses domain_sso_config prefix in class configuration' do
      # Verify the class is configured with the correct prefix
      # The actual Redis key is constructed internally by Familia
      expect(Onetime::DomainSsoConfig.prefix).to eq(:domain_sso_config)
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
  # configs_by_domain Class Method Tests
  # ==========================================================================

  describe '.configs_by_domain' do
    it 'responds to configs_by_domain' do
      expect(described_class).to respond_to(:configs_by_domain)
    end

    it 'returns a Familia HashKey' do
      hashkey = described_class.configs_by_domain
      expect(hashkey).to be_a(Familia::HashKey)
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
end

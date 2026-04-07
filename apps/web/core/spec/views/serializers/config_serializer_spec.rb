# apps/web/core/spec/views/serializers/config_serializer_spec.rb
#
# frozen_string_literal: true

# Unit tests for ConfigSerializer domain-aware SSO provider resolution
#
# Tests cover:
# - Tenant SSO config resolution from custom domain
# - Platform fallback behavior
# - Edge cases (disabled config, missing domain, Redis errors)
#
# Run with:
#   source .env.test && bundle exec rspec apps/web/core/spec/views/serializers/config_serializer_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../views/serializers'
require_relative File.join(Onetime::HOME, 'apps', 'web', 'auth', 'spec', 'support', 'tenant_test_fixtures')
require_relative File.join(Onetime::HOME, 'apps', 'web', 'auth', 'spec', 'support', 'domain_sso_test_fixtures')

RSpec.describe Core::Views::ConfigSerializer do
  include TenantTestFixtures
  include DomainSsoTestFixtures

  # Configure Familia encryption for CustomDomain::SsoConfig tests
  before(:all) do
    @original_encryption_keys = Familia.encryption_keys&.dup
    @original_key_version = Familia.current_key_version
    @original_personalization = Familia.encryption_personalization

    key_v1 = 'test_encryption_key_32bytes_ok!!'
    key_v2 = 'another_test_key_for_testing_!!'

    Familia.configure do |config|
      config.encryption_keys = {
        v1: Base64.strict_encode64(key_v1),
        v2: Base64.strict_encode64(key_v2),
      }
      config.current_key_version = :v1
      config.encryption_personalization = 'ConfigSerializerTest'
    end
  end

  after(:all) do
    Familia.configure do |config|
      config.encryption_keys = @original_encryption_keys if @original_encryption_keys
      config.current_key_version = @original_key_version if @original_key_version
      config.encryption_personalization = @original_personalization if @original_personalization
    end
  end

  let(:canonical_domain) { 'onetimesecret.com' }
  let(:custom_display_domain) { 'secrets.acme.com' }
  let(:domain_id) { DomainSsoTestFixtures::SAMPLE_DOMAIN_IDS[:primary] }

  let(:customer) do
    instance_double(
      Onetime::Customer,
      custom_domains_list: []
    )
  end

  let(:session) { {} }

  # Base view_vars for canonical domain (no custom domain)
  let(:base_view_vars) do
    {
      'authenticated' => false,
      'cust' => customer,
      'sess' => session,
      'site' => {
        'host' => canonical_domain,
        'ssl' => true,
        'interface' => { 'ui' => {} },
        'authentication' => {},
        'secret_options' => {},
        'support' => { 'host' => 'support.example.com' },
      },
      'features' => {
        'regions' => { 'enabled' => false },
        'domains' => { 'enabled' => false },
      },
      'development' => { 'enabled' => false, 'domain_context_enabled' => false },
      'diagnostics' => { 'sentry' => {} },
      'homepage_mode' => nil,
      'domain_strategy' => :canonical,
      'display_domain' => canonical_domain,
      'organization' => nil,
    }
  end

  # Mock auth config for SSO state
  let(:mock_auth_config) do
    instance_double(
      Onetime::AuthConfig,
      lockout_enabled?: false,
      password_requirements_enabled?: false,
      active_sessions_enabled?: false,
      remember_me_enabled?: false,
      mfa_enabled?: false,
      email_auth_enabled?: false,
      webauthn_enabled?: false,
      sso_enabled?: false,
      sso_only_enabled?: false,
      restrict_to: nil,
      sso_providers: [],
      allow_platform_fallback_for_tenants?: false
    )
  end

  before do
    allow(Onetime).to receive(:auth_config).and_return(mock_auth_config)
    allow(OT).to receive(:conf).and_return({})
  end

  describe '.output_template' do
    it 'includes features field' do
      template = described_class.output_template
      expect(template).to have_key('features')
    end
  end

  describe '.serialize' do
    it 'returns a hash with features key' do
      result = described_class.serialize(base_view_vars)
      expect(result).to have_key('features')
    end

    it 'includes sso in features' do
      result = described_class.serialize(base_view_vars)
      expect(result['features']).to have_key('sso')
    end
  end

  describe '.build_sso_config' do
    describe 'on canonical domain (no tenant)' do
      context 'when platform SSO is disabled' do
        before do
          allow(mock_auth_config).to receive(:sso_enabled?).and_return(false)
        end

        it 'returns false' do
          result = described_class.build_sso_config(base_view_vars)
          expect(result).to be false
        end
      end

      context 'when platform SSO is enabled with providers' do
        before do
          allow(mock_auth_config).to receive(:sso_enabled?).and_return(true)
          allow(mock_auth_config).to receive(:sso_providers).and_return([
            { 'route_name' => 'oidc', 'display_name' => 'Corporate SSO' },
          ])
        end

        it 'returns platform providers' do
          result = described_class.build_sso_config(base_view_vars)
          expect(result).to eq({
            'enabled' => true,
            'providers' => [
              { 'route_name' => 'oidc', 'display_name' => 'Corporate SSO' },
            ],
          })
        end
      end
    end

    describe 'on custom domain with CustomDomain::SsoConfig' do
      let(:custom_domain_obj) do
        instance_double(Onetime::CustomDomain, identifier: domain_id)
      end

      let(:custom_domain_view_vars) do
        base_view_vars.merge(
          'domain_strategy' => :custom,
          'display_domain' => custom_display_domain
        )
      end

      context 'when tenant has enabled CustomDomain::SsoConfig' do
        let(:domain_sso_config) do
          instance_double(
            Onetime::CustomDomain::SsoConfig,
            enabled?: true,
            provider_type: 'entra_id',
            display_name: 'Contoso Azure AD',
            platform_route_name: 'entra'
          )
        end

        before do
          allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
            .with(custom_display_domain)
            .and_return(custom_domain_obj)
          allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
            .with(domain_id)
            .and_return(domain_sso_config)
        end

        it 'returns tenant provider' do
          result = described_class.build_sso_config(custom_domain_view_vars)

          expect(result['enabled']).to be true
          expect(result['providers'].length).to eq(1)
          expect(result['providers'][0]['route_name']).to eq('entra')
          expect(result['providers'][0]['display_name']).to eq('Contoso Azure AD')
        end

        it 'does not call platform sso_providers' do
          expect(mock_auth_config).not_to receive(:sso_providers)
          described_class.build_sso_config(custom_domain_view_vars)
        end
      end

      context 'when tenant has disabled CustomDomain::SsoConfig' do
        let(:domain_sso_config) do
          instance_double(
            Onetime::CustomDomain::SsoConfig,
            enabled?: false,
            provider_type: 'entra_id',
            display_name: 'Contoso Azure AD'
          )
        end

        before do
          allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
            .with(custom_display_domain)
            .and_return(custom_domain_obj)
          allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
            .with(domain_id)
            .and_return(domain_sso_config)
        end

        context 'with platform fallback allowed' do
          before do
            allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
            allow(mock_auth_config).to receive(:sso_enabled?).and_return(true)
            allow(mock_auth_config).to receive(:sso_providers).and_return([
              { 'route_name' => 'oidc', 'display_name' => 'Platform SSO' },
            ])
          end

          it 'falls back to platform providers' do
            result = described_class.build_sso_config(custom_domain_view_vars)

            expect(result['enabled']).to be true
            expect(result['providers'][0]['display_name']).to eq('Platform SSO')
          end
        end

        context 'with platform fallback denied (default)' do
          before do
            allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(false)
          end

          it 'returns disabled SSO with empty providers' do
            result = described_class.build_sso_config(custom_domain_view_vars)

            expect(result['enabled']).to be false
            expect(result['providers']).to eq([])
          end
        end
      end

      context 'when tenant has no CustomDomain::SsoConfig' do
        before do
          allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
            .with(custom_display_domain)
            .and_return(custom_domain_obj)
          allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
            .with(domain_id)
            .and_return(nil)
        end

        context 'with platform fallback allowed' do
          before do
            allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
            allow(mock_auth_config).to receive(:sso_enabled?).and_return(true)
            allow(mock_auth_config).to receive(:sso_providers).and_return([
              { 'route_name' => 'google', 'display_name' => 'Google' },
            ])
          end

          it 'falls back to platform providers' do
            result = described_class.build_sso_config(custom_domain_view_vars)

            expect(result['enabled']).to be true
            expect(result['providers'][0]['route_name']).to eq('google')
          end
        end

        context 'with platform fallback denied (default)' do
          before do
            allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(false)
          end

          it 'returns disabled SSO' do
            result = described_class.build_sso_config(custom_domain_view_vars)

            expect(result['enabled']).to be false
            expect(result['providers']).to eq([])
          end
        end
      end
    end

    describe 'custom domain resolution from display_domain' do
      let(:custom_domain_obj) do
        instance_double(Onetime::CustomDomain, identifier: domain_id)
      end

      let(:custom_domain_view_vars) do
        base_view_vars.merge(
          'domain_strategy' => :custom,
          'display_domain' => custom_display_domain
        )
      end

      context 'when CustomDomain exists with CustomDomain::SsoConfig' do
        let(:domain_sso_config) do
          instance_double(
            Onetime::CustomDomain::SsoConfig,
            enabled?: true,
            provider_type: 'entra_id',
            display_name: 'Acme Corp Entra',
            platform_route_name: 'entra'
          )
        end

        before do
          allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
            .with(custom_display_domain)
            .and_return(custom_domain_obj)
          allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
            .with(domain_id)
            .and_return(domain_sso_config)
        end

        it 'resolves tenant config from CustomDomain::SsoConfig' do
          result = described_class.build_sso_config(custom_domain_view_vars)

          expect(result['enabled']).to be true
          expect(result['providers'][0]['route_name']).to eq('entra')
          expect(result['providers'][0]['display_name']).to eq('Acme Corp Entra')
        end
      end

      context 'when CustomDomain lookup fails (Redis error)' do
        before do
          allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
            .and_raise(Redis::ConnectionError.new('Connection refused'))
          allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
          allow(mock_auth_config).to receive(:sso_enabled?).and_return(true)
          allow(mock_auth_config).to receive(:sso_providers).and_return([
            { 'route_name' => 'oidc', 'display_name' => 'Fallback SSO' },
          ])
        end

        it 'gracefully falls back to platform SSO' do
          result = described_class.build_sso_config(custom_domain_view_vars)

          # Should not raise, should fall back
          expect(result['enabled']).to be true
          expect(result['providers'][0]['display_name']).to eq('Fallback SSO')
        end
      end
    end
  end

  describe '.resolve_domain_id' do
    context 'with display_domain' do
      let(:custom_domain_obj) do
        instance_double(Onetime::CustomDomain, identifier: domain_id)
      end

      before do
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
          .with(custom_display_domain)
          .and_return(custom_domain_obj)
      end

      it 'resolves from CustomDomain' do
        vars = base_view_vars.merge(
          'display_domain' => custom_display_domain
        )
        result = described_class.resolve_domain_id(vars)
        expect(result).to eq(domain_id)
      end
    end

    context 'with empty display_domain' do
      it 'returns nil' do
        vars = base_view_vars.merge(
          'display_domain' => ''
        )
        result = described_class.resolve_domain_id(vars)
        expect(result).to be_nil
      end
    end

    context 'when CustomDomain not found' do
      before do
        allow(Onetime::CustomDomain).to receive(:load_by_display_domain)
          .and_return(nil)
      end

      it 'returns nil' do
        vars = base_view_vars.merge(
          'display_domain' => 'unknown.example.com'
        )
        result = described_class.resolve_domain_id(vars)
        expect(result).to be_nil
      end
    end
  end

  describe '.tenant_domain?' do
    it 'returns true for :custom domain_strategy' do
      vars = base_view_vars.merge('domain_strategy' => :custom)
      expect(described_class.tenant_domain?(vars)).to be true
    end

    it 'returns false for :canonical domain_strategy' do
      vars = base_view_vars.merge('domain_strategy' => :canonical)
      expect(described_class.tenant_domain?(vars)).to be false
    end

    it 'returns false for :subdomain domain_strategy' do
      vars = base_view_vars.merge('domain_strategy' => :subdomain)
      expect(described_class.tenant_domain?(vars)).to be false
    end
  end

  describe '.allow_platform_fallback?' do
    context 'when not configured (default is false per #2918)' do
      it 'returns false' do
        expect(described_class.allow_platform_fallback?).to be false
      end
    end

    context 'when auth_config returns true' do
      before do
        allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
      end

      it 'returns true' do
        expect(described_class.allow_platform_fallback?).to be true
      end
    end

    context 'when auth_config returns false' do
      before do
        allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(false)
      end

      it 'returns false' do
        expect(described_class.allow_platform_fallback?).to be false
      end
    end
  end

  describe '.build_tenant_sso_response' do
    it 'returns correct structure for OIDC config' do
      config = build_domain_sso_config(:oidc, display_name: 'Acme SSO')
      result = described_class.build_tenant_sso_response(config)

      expect(result).to eq({
        'enabled' => true,
        'providers' => [
          { 'route_name' => 'oidc', 'display_name' => 'Acme SSO' },
        ],
      })
    end

    it 'returns correct structure for Entra ID config' do
      config = build_domain_sso_config(:entra_id, display_name: 'Microsoft Login')
      result = described_class.build_tenant_sso_response(config)

      expect(result).to eq({
        'enabled' => true,
        'providers' => [
          { 'route_name' => 'entra', 'display_name' => 'Microsoft Login' },
        ],
      })
    end

    it 'handles nil display_name gracefully' do
      config = build_domain_sso_config(:github)
      allow(config).to receive(:display_name).and_return(nil)

      result = described_class.build_tenant_sso_response(config)

      expect(result['providers'][0]['display_name']).to eq('')
    end
  end
end

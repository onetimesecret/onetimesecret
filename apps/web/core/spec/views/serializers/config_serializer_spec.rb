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
        'interface' => {
          'ui' => {},
          'api' => {
            'enabled' => true,
            'guest_routes' => {
              'enabled' => true,
              'conceal' => true,
              'generate' => true,
              'reveal' => true,
              'burn' => true,
              'show' => true,
              'receipt' => true,
            },
          },
        },
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

    describe 'brand_* bootstrap exposure' do
      let(:brand_view_vars) do
        base_view_vars.merge(
          'brand_primary_color' => '#112233',
          'brand_product_name' => 'Acme Vault',
          'brand_product_domain' => 'vault.acme.test',
          'brand_support_email' => 'help@acme.test',
          'brand_corner_style' => 'square',
          'brand_font_family' => 'serif',
          'brand_button_text_light' => false,
          'brand_logo_url' => 'https://acme.test/logo.svg',
          'brand_totp_issuer' => 'Acme',
          'support_email' => 'help@acme.test',
          'docs_host' => 'https://docs.acme.test/'
        )
      end

      it 'copies brand_primary_color from view_vars to output' do
        result = described_class.serialize(brand_view_vars)
        expect(result['brand_primary_color']).to eq('#112233')
      end

      it 'copies brand_product_name from view_vars to output' do
        result = described_class.serialize(brand_view_vars)
        expect(result['brand_product_name']).to eq('Acme Vault')
      end

      it 'copies brand_product_domain from view_vars to output' do
        result = described_class.serialize(brand_view_vars)
        expect(result['brand_product_domain']).to eq('vault.acme.test')
      end

      it 'copies brand_support_email from view_vars to output' do
        result = described_class.serialize(brand_view_vars)
        expect(result['brand_support_email']).to eq('help@acme.test')
      end

      it 'copies brand_corner_style from view_vars to output' do
        result = described_class.serialize(brand_view_vars)
        expect(result['brand_corner_style']).to eq('square')
      end

      it 'copies brand_font_family from view_vars to output' do
        result = described_class.serialize(brand_view_vars)
        expect(result['brand_font_family']).to eq('serif')
      end

      it 'copies brand_button_text_light from view_vars to output' do
        result = described_class.serialize(brand_view_vars)
        expect(result['brand_button_text_light']).to be false
      end

      it 'copies brand_logo_url from view_vars to output' do
        result = described_class.serialize(brand_view_vars)
        expect(result['brand_logo_url']).to eq('https://acme.test/logo.svg')
      end

      it 'copies brand_totp_issuer from view_vars to output' do
        result = described_class.serialize(brand_view_vars)
        expect(result['brand_totp_issuer']).to eq('Acme')
      end

      it 'copies support_email from view_vars to output' do
        result = described_class.serialize(brand_view_vars)
        expect(result['support_email']).to eq('help@acme.test')
      end

      it 'copies docs_host from view_vars to output' do
        result = described_class.serialize(brand_view_vars)
        expect(result['docs_host']).to eq('https://docs.acme.test/')
      end

      it 'leaves brand_* keys nil when view_vars omits them' do
        result = described_class.serialize(base_view_vars)
        %w[
          brand_primary_color
          brand_product_name
          brand_product_domain
          brand_support_email
          brand_corner_style
          brand_font_family
          brand_button_text_light
          brand_logo_url
          brand_totp_issuer
        ].each do |key|
          expect(result[key]).to be_nil, "expected #{key} to be nil when view_vars omits it"
        end
      end

      it 'includes every brand_* key in the output_template (single source of truth)' do
        template_keys = described_class.output_template.keys
        %w[
          brand_primary_color
          brand_product_name
          brand_product_domain
          brand_support_email
          brand_corner_style
          brand_font_family
          brand_button_text_light
          brand_logo_url
          brand_totp_issuer
        ].each do |key|
          expect(template_keys).to include(key), "output_template missing #{key}"
        end
      end

      it 'includes general config keys in the output_template' do
        template_keys = described_class.output_template.keys
        %w[support_email docs_host].each do |key|
          expect(template_keys).to include(key), "output_template missing #{key}"
        end
      end
    end

    it 'returns api as a nested object with enabled and guest_routes' do
      result = described_class.serialize(base_view_vars)
      expect(result).to have_key('api')
      expect(result['api']).to be_a(Hash)
      expect(result['api']['enabled']).to be true
      expect(result['api']['guest_routes']).to be_a(Hash)
      expect(result['api']['guest_routes']['conceal']).to be true
    end

    context 'when api config is missing' do
      let(:minimal_view_vars) do
        base_view_vars.merge(
          'site' => base_view_vars['site'].merge('interface' => { 'ui' => {} })
        )
      end

      it 'defaults api.enabled to true and guest_routes to empty hash' do
        result = described_class.serialize(minimal_view_vars)
        expect(result['api']['enabled']).to be true
        expect(result['api']['guest_routes']).to eq({})
      end
    end

    context 'when api.enabled is explicitly false' do
      let(:api_disabled_view_vars) do
        base_view_vars.merge(
          'site' => base_view_vars['site'].merge(
            'interface' => {
              'ui' => {},
              'api' => { 'enabled' => false, 'guest_routes' => {} },
            }
          )
        )
      end

      it 'returns api.enabled as false' do
        result = described_class.serialize(api_disabled_view_vars)
        expect(result['api']['enabled']).to be false
      end
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
            platform_route_name: 'entra',
            enforce_sso_only?: false
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
            platform_route_name: 'entra',
            enforce_sso_only?: false
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

  describe '.build_feature_flags' do
    describe 'organizations feature flags' do
      context 'when no organizations config is present' do
        it 'defaults all organization flags to false' do
          result = described_class.build_feature_flags(base_view_vars)
          orgs = result['organizations']

          expect(orgs['enabled']).to be false
          expect(orgs['sso_enabled']).to be false
          expect(orgs['custom_mail_enabled']).to be false
          expect(orgs['incoming_secrets_enabled']).to be false
        end
      end

      context 'when features key is empty' do
        it 'defaults all organization flags to false' do
          result = described_class.build_feature_flags({ 'features' => {} })
          orgs = result['organizations']

          expect(orgs['custom_mail_enabled']).to be false
          expect(orgs['incoming_secrets_enabled']).to be false
        end
      end

      context 'when custom_mail_enabled is true' do
        let(:view_vars_with_custom_mail) do
          base_view_vars.merge(
            'features' => base_view_vars['features'].merge(
              'organizations' => { 'enabled' => false, 'custom_mail_enabled' => true }
            )
          )
        end

        it 'includes custom_mail_enabled as true' do
          result = described_class.build_feature_flags(view_vars_with_custom_mail)

          expect(result['organizations']['custom_mail_enabled']).to be true
        end

        it 'does not affect other organization flags' do
          result = described_class.build_feature_flags(view_vars_with_custom_mail)
          orgs = result['organizations']

          expect(orgs['enabled']).to be false
          expect(orgs['sso_enabled']).to be false
          expect(orgs['incoming_secrets_enabled']).to be false
        end
      end

      context 'when incoming_secrets_enabled is true' do
        let(:view_vars_with_incoming) do
          base_view_vars.merge(
            'features' => base_view_vars['features'].merge(
              'organizations' => { 'enabled' => false, 'incoming_secrets_enabled' => true }
            )
          )
        end

        it 'includes incoming_secrets_enabled as true' do
          result = described_class.build_feature_flags(view_vars_with_incoming)

          expect(result['organizations']['incoming_secrets_enabled']).to be true
        end

        it 'does not affect other organization flags' do
          result = described_class.build_feature_flags(view_vars_with_incoming)
          orgs = result['organizations']

          expect(orgs['enabled']).to be false
          expect(orgs['sso_enabled']).to be false
          expect(orgs['custom_mail_enabled']).to be false
        end
      end

      context 'when all organization flags are enabled' do
        let(:view_vars_all_orgs) do
          base_view_vars.merge(
            'features' => base_view_vars['features'].merge(
              'organizations' => {
                'enabled' => true,
                'sso_enabled' => true,
                'custom_mail_enabled' => true,
                'incoming_secrets_enabled' => true,
              }
            )
          )
        end

        it 'includes all flags as true' do
          result = described_class.build_feature_flags(view_vars_all_orgs)
          orgs = result['organizations']

          expect(orgs['enabled']).to be true
          expect(orgs['sso_enabled']).to be true
          expect(orgs['custom_mail_enabled']).to be true
          expect(orgs['incoming_secrets_enabled']).to be true
        end
      end

      context 'when custom_mail_enabled and incoming_secrets_enabled are independent of sso_enabled' do
        let(:view_vars_mail_and_incoming_only) do
          base_view_vars.merge(
            'features' => base_view_vars['features'].merge(
              'organizations' => {
                'enabled' => true,
                'sso_enabled' => false,
                'custom_mail_enabled' => true,
                'incoming_secrets_enabled' => true,
              }
            )
          )
        end

        it 'allows custom_mail and incoming_secrets without sso' do
          result = described_class.build_feature_flags(view_vars_mail_and_incoming_only)
          orgs = result['organizations']

          expect(orgs['sso_enabled']).to be false
          expect(orgs['custom_mail_enabled']).to be true
          expect(orgs['incoming_secrets_enabled']).to be true
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

  describe '.transform_regions' do
    it 'returns enabled false and empty jurisdictions for empty regions config' do
      result = described_class.transform_regions({})

      expect(result['enabled']).to be false
      expect(result['jurisdictions']).to eq([])
      expect(result['current_jurisdiction']).to be_nil
    end

    it 'transforms jurisdictions with identifier, domain, and i18n key' do
      regions = {
        'enabled' => true,
        'current_jurisdiction' => 'EU',
        'jurisdictions' => [
          { 'identifier' => 'EU', 'domain' => 'eu.example.com' },
          { 'identifier' => 'CA', 'domain' => 'ca.example.com' },
        ],
      }

      result = described_class.transform_regions(regions)

      expect(result['enabled']).to be true
      expect(result['current_jurisdiction']).to eq('EU')
      expect(result['jurisdictions'].length).to eq(2)
      expect(result['jurisdictions'][0]).to eq({
        'identifier' => 'EU',
        'domain' => 'eu.example.com',
        'display_name_i18n_key' => 'web.regions.jurisdictions.eu.name',
      })
      expect(result['jurisdictions'][1]).to eq({
        'identifier' => 'CA',
        'domain' => 'ca.example.com',
        'display_name_i18n_key' => 'web.regions.jurisdictions.ca.name',
      })
    end

    it 'includes domain in output for navigation' do
      regions = {
        'enabled' => true,
        'jurisdictions' => [
          { 'identifier' => 'EU', 'domain' => 'eu.onetimesecret.com' },
        ],
      }

      result = described_class.transform_regions(regions)

      expect(result['jurisdictions'][0]['domain']).to eq('eu.onetimesecret.com')
    end

    it 'includes icon when present in config' do
      regions = {
        'enabled' => true,
        'jurisdictions' => [
          {
            'identifier' => 'EU',
            'domain' => 'eu.example.com',
            'icon' => { 'collection' => 'fa6-solid', 'name' => 'earth-europe' },
          },
        ],
      }

      result = described_class.transform_regions(regions)

      expect(result['jurisdictions'][0]['icon']).to eq({
        'collection' => 'fa6-solid',
        'name' => 'earth-europe',
      })
    end

    it 'omits icon when not present in config' do
      regions = {
        'enabled' => true,
        'jurisdictions' => [
          { 'identifier' => 'EU', 'domain' => 'eu.example.com' },
        ],
      }

      result = described_class.transform_regions(regions)

      expect(result['jurisdictions'][0]).not_to have_key('icon')
    end

    it 'lowercases identifier for i18n key generation' do
      regions = {
        'enabled' => false,
        'jurisdictions' => [
          { 'identifier' => 'US-WEST', 'domain' => 'west.example.com' },
        ],
      }

      result = described_class.transform_regions(regions)

      expect(result['jurisdictions'][0]['display_name_i18n_key']).to eq('web.regions.jurisdictions.us-west.name')
    end

    it 'uses display_name_i18n_key from config when provided' do
      regions = {
        'enabled' => true,
        'jurisdictions' => [
          {
            'identifier' => 'EU',
            'domain' => 'eu.example.com',
            'display_name_i18n_key' => 'custom.key.eu',
          },
        ],
      }

      result = described_class.transform_regions(regions)

      expect(result['jurisdictions'][0]['display_name_i18n_key']).to eq('custom.key.eu')
    end

    it 'handles jurisdictions with nil identifier gracefully' do
      regions = {
        'enabled' => true,
        'jurisdictions' => [
          { 'identifier' => nil, 'domain' => 'example.com' },
        ],
      }

      result = described_class.transform_regions(regions)

      expect(result['jurisdictions'][0]['identifier']).to eq('')
      expect(result['jurisdictions'][0]['domain']).to eq('example.com')
      expect(result['jurisdictions'][0]['display_name_i18n_key']).to eq('web.regions.jurisdictions..name')
    end
  end

  describe '.build_tenant_sso_response' do
    it 'returns correct structure for OIDC config' do
      config = build_domain_sso_config(:oidc, display_name: 'Acme SSO')
      result = described_class.build_tenant_sso_response(config)

      expect(result).to eq({
        'enabled' => true,
        'enforce_sso_only' => false,
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
        'enforce_sso_only' => false,
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

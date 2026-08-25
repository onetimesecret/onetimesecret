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
      config.encryption_personalization = 'ConfigSerialTest'
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
      # Post-boot availability of the global restriction
      # (ADR-034#degradation-is-fail-closed): the
      # serializer now hands it to the resolver instead of ignoring it (#4139).
      restrict_to_available?: true,
      sso_providers: [],
      allow_platform_fallback_for_tenants?: false
    )
  end

  before do
    allow(Onetime).to receive(:auth_config).and_return(mock_auth_config)
    # Master switch on: tenant_sso_available_for? consults
    # SigninConfig.global_auth_enabled (AUTH_ENABLED) before the credential
    # checks, and these examples exercise the credential/permission gates.
    allow(OT).to receive(:conf).and_return(
      { 'site' => { 'authentication' => { 'enabled' => true } } }
    )
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

    # The web UI filters durations against the server-resolved guest ceiling.
    # Canonical guests use the configured anonymous policy (7 days by default);
    # custom-domain guests use the domain owner organization's plan policy.
    # This distinction must match API enforcement.
    describe 'secret_options.ttl_max_anonymous' do
      let(:default_ceiling) { Onetime::Models::Features::WithEntitlements::ANONYMOUS_MAX_TTL }

      let(:ttl_view_vars) do
        base_view_vars.merge(
          'site' => base_view_vars['site'].merge(
            'secret_options' => { 'default_ttl' => 86_400, 'ttl_options' => [3600, 2_592_000] }
          )
        )
      end

      def secret_options
        described_class.serialize(ttl_view_vars)['secret_options']
      end

      # Stub the resolved config key rather than OT.conf, so these specs pin the
      # serializer's ladder and not the config layer's ERB/alias plumbing.
      def stub_configured_ceiling(seconds)
        allow(Onetime::Models::Features::WithEntitlements)
          .to receive(:configured_anonymous_max_ttl).and_return(seconds)
      end

      it 'defaults below the free-tier ceiling' do
        expect(default_ceiling).to be < Onetime::Models::Features::WithEntitlements::DEFAULT_FREE_TTL
      end

      context 'when billing is enabled' do
        before do
          allow(OT.billing_config).to receive(:enabled?).and_return(true)
          allow(Onetime::Organization).to receive(:free_tier_limits)
            .and_return({ 'secret_lifetime.max' => 1_209_600 })
        end

        it 'publishes the configured ceiling alongside the configured options' do
          expect(secret_options['ttl_max_anonymous']).to eq(default_ceiling)
          expect(secret_options['ttl_options']).to eq([3600, 2_592_000])
        end

        it 'lets the free-tier limit lower the ceiling' do
          allow(Onetime::Organization).to receive(:free_tier_limits)
            .and_return({ 'secret_lifetime.max' => 86_400 })

          expect(secret_options['ttl_max_anonymous']).to eq(86_400)
        end

        # The audit invariant, holding where tiers exist: an operator who raises
        # the anonymous ceiling above the free-tier limit must not widen the
        # dropdown past what a signed-in free-tier user can get.
        it 'caps a raised ceiling at the free-tier limit' do
          stub_configured_ceiling(2_592_000)

          expect(secret_options['ttl_max_anonymous']).to eq(1_209_600)
        end

        it 'reads a non-positive free-tier limit as "unset" and keeps the ceiling' do
          allow(Onetime::Organization).to receive(:free_tier_limits)
            .and_return({ 'secret_lifetime.max' => 0 })

          expect(secret_options['ttl_max_anonymous']).to eq(default_ceiling)
        end

        it 'drops only the free-tier term, not the ceiling, when the lookup raises' do
          allow(Onetime::Organization).to receive(:free_tier_limits).and_raise(
            StandardError, 'billing config unreadable'
          )
          allow(OT).to receive(:le)

          expect(secret_options['ttl_max_anonymous']).to eq(default_ceiling)
          expect(OT).to have_received(:le).with(
            a_string_matching(/Canonical guest TTL resolution failed/),
            hash_including(:exception, ceiling: default_ceiling),
          )
        end

        it 'does not mutate the site config hash' do
          site_options = ttl_view_vars['site']['secret_options']
          secret_options

          expect(site_options).not_to have_key('ttl_max_anonymous')
        end
      end

      context 'when billing is disabled (self-hosted)' do
        before { allow(OT.billing_config).to receive(:enabled?).and_return(false) }

        # The canonical guest ceiling is about anonymous callers, not about
        # whether the deployment sells plans, so it is still emitted.
        it 'still publishes the configured ceiling' do
          expect(secret_options['ttl_max_anonymous']).to eq(default_ceiling)
        end

        it 'ignores the free-tier limit entirely' do
          allow(Onetime::Organization).to receive(:free_tier_limits)
            .and_return({ 'secret_lifetime.max' => 60 })

          expect(secret_options['ttl_max_anonymous']).to eq(default_ceiling)
        end

        # Self-hosted sovereignty: with no free tier to invert against, the
        # operator's raised ceiling reaches the dropdown unchanged.
        it 'publishes a ceiling the operator raised above the default' do
          stub_configured_ceiling(2_592_000)

          expect(secret_options['ttl_max_anonymous']).to eq(2_592_000)
        end
      end

      context 'on a branded custom domain' do
        let(:domain) do
          instance_double(
            Onetime::CustomDomain,
            org_id: 'org-custom',
            identifier: domain_id,
          )
        end
        let(:organization) { instance_double(Onetime::Organization) }
        let(:ttl_view_vars) do
          super().merge(
            'domain_strategy' => :custom,
            'display_domain' => custom_display_domain,
          )
        end

        before do
          allow(OT.billing_config).to receive(:enabled?).and_return(true)
          allow(Onetime::CustomDomain).to receive(:from_display_domain)
            .with(custom_display_domain).and_return(domain)
          allow(Onetime::Organization).to receive(:load)
            .with('org-custom').and_return(organization)
        end

        it 'publishes the domain owner free-plan lifetime, not the canonical 7-day ceiling' do
          allow(organization).to receive(:limit_for)
            .with('secret_lifetime').and_return(1_209_600)

          expect(secret_options['ttl_max_anonymous']).to eq(1_209_600)
        end

        it 'publishes the domain owner extended lifetime, not the canonical 7-day ceiling' do
          allow(organization).to receive(:limit_for)
            .with('secret_lifetime').and_return(2_592_000)
          allow(organization).to receive(:can?)
            .with('extended_default_expiration').and_return(true)

          expect(secret_options['ttl_max_anonymous']).to eq(2_592_000)
        end
      end
    end

    # The features.domains config subtree carries the Approximated proxy
    # credentials (approximated.api_key et al.) and the internal ACME
    # listener config. The bootstrap payload is served to every visitor, so
    # the serializer must allowlist the frontend-facing fields instead of
    # passing the subtree through verbatim. DNS proxy targets for domain
    # owners are served by the authenticated domains API
    # (DomainValidation::Features.safe_dump), not the bootstrap.
    describe 'domains allowlist' do
      let(:domains_config) do
        {
          'enabled' => true,
          'require_verified' => true,
          'default' => 'eu.example.com',
          'validation_strategy' => 'approximated',
          'approximated' => {
            'api_key' => 'secret-api-key',
            'proxy_ip' => '203.0.113.10',
            'proxy_host' => 'proxy.example.net',
            'proxy_name' => 'proxy',
            'vhost_target' => 'target.example.net',
          },
          'acme' => {
            'enabled' => true,
            'listen_address' => '127.0.0.1',
            'port' => 12_020,
          },
        }
      end

      let(:domains_view_vars) do
        base_view_vars.merge(
          'features' => base_view_vars['features'].merge('domains' => domains_config)
        )
      end

      it 'emits only the allowlisted fields' do
        result = described_class.serialize(domains_view_vars)
        expect(result['domains']).to eq(
          'enabled' => true,
          'require_verified' => true,
          'default' => 'eu.example.com',
          'validation_strategy' => 'approximated'
        )
      end

      it 'never emits the Approximated credentials or ACME config' do
        result = described_class.serialize(domains_view_vars)
        expect(result['domains']).not_to have_key('approximated')
        expect(result['domains']).not_to have_key('acme')
        expect(result.to_s).not_to include('secret-api-key')
      end

      it 'omits the domains key entirely when the feature is disabled' do
        result = described_class.serialize(base_view_vars)
        expect(result['domains_enabled']).to be(false)
        expect(result['domains']).to be_nil
      end
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
          'brand_logo_alt' => 'Acme Vault wordmark',
          'brand_favicon_url' => 'https://acme.test/favicon.png',
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

      it 'copies brand_logo_alt from view_vars to output' do
        result = described_class.serialize(brand_view_vars)
        expect(result['brand_logo_alt']).to eq('Acme Vault wordmark')
      end

      it 'copies brand_favicon_url from view_vars to output' do
        result = described_class.serialize(brand_view_vars)
        expect(result['brand_favicon_url']).to eq('https://acme.test/favicon.png')
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
          brand_logo_dark_url
          brand_logo_alt
          brand_favicon_url
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
          brand_logo_dark_url
          brand_logo_alt
          brand_favicon_url
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

      context 'when platform SSO is enabled but AUTH_ENABLED is off' do
        before do
          allow(mock_auth_config).to receive(:sso_enabled?).and_return(true)
          allow(mock_auth_config).to receive(:sso_providers).and_return([
            { 'route_name' => 'oidc', 'display_name' => 'Corporate SSO' },
          ])
          # Master switch off: build_sso_config early-returns the disabled
          # shape before consulting env-var provider config
          # (build_platform_sso_config re-checks as defense in depth).
          allow(OT).to receive(:conf).and_return(
            { 'site' => { 'authentication' => { 'enabled' => false } } }
          )
        end

        it 'returns disabled SSO with empty providers' do
          result = described_class.build_sso_config(base_view_vars)
          expect(result).to eq({ 'enabled' => false, 'providers' => [] })
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
            domain_id: domain_id,
            enabled?: true,
            provider_type: 'entra_id',
            display_name: 'Contoso Azure AD',
            platform_route_name: 'entra',
            enforce_sso_only?: false
          )
        end

        before do
          allow(Onetime::CustomDomain).to receive(:from_display_domain)
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

        # Single-read contract: the availability check and the returned
        # record must come from ONE find_by_domain_id call, so a concurrent
        # disable/delete cannot pass the check on one read and hand back a
        # stale (or nil) record on a second.
        it 'loads the SsoConfig once and returns the record the availability check saw' do
          expect(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
            .with(domain_id)
            .once
            .and_return(domain_sso_config)

          result = described_class.resolve_tenant_sso_config(custom_domain_view_vars)

          expect(result).to be(domain_sso_config)
        end
      end

      context 'when SigninConfig blocks SSO (sso_permitted_for? returns false)' do
        let(:domain_sso_config) do
          instance_double(
            Onetime::CustomDomain::SsoConfig,
            domain_id: domain_id,
            enabled?: true,
            provider_type: 'oidc',
            display_name: 'Corp SSO',
            platform_route_name: 'oidc',
            enforce_sso_only?: false
          )
        end

        before do
          allow(Onetime::CustomDomain).to receive(:from_display_domain)
            .with(custom_display_domain)
            .and_return(custom_domain_obj)
          allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
            .with(domain_id)
            .and_return(domain_sso_config)
          # SigninConfig gate blocks SSO for this domain
          allow(Onetime::CustomDomain::SigninConfig).to receive(:sso_permitted_for?)
            .with(domain_id)
            .and_return(false)
        end

        context 'with platform fallback denied (default)' do
          before do
            allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(false)
          end

          it 'returns disabled SSO (SigninConfig gate overrides SsoConfig)' do
            result = described_class.build_sso_config(custom_domain_view_vars)

            expect(result['enabled']).to be false
            expect(result['providers']).to eq([])
          end
        end

        context 'with platform fallback allowed' do
          before do
            allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
            allow(mock_auth_config).to receive(:sso_enabled?).and_return(true)
            allow(mock_auth_config).to receive(:sso_providers).and_return([
              { 'route_name' => 'oidc', 'display_name' => 'Platform SSO' },
            ])
          end

          it 'falls back to platform SSO (SigninConfig blocks tenant, not platform)' do
            result = described_class.build_sso_config(custom_domain_view_vars)

            expect(result['enabled']).to be true
            expect(result['providers'][0]['display_name']).to eq('Platform SSO')
          end
        end
      end

      context 'when tenant has disabled CustomDomain::SsoConfig' do
        let(:domain_sso_config) do
          instance_double(
            Onetime::CustomDomain::SsoConfig,
            domain_id: domain_id,
            enabled?: false,
            provider_type: 'entra_id',
            display_name: 'Contoso Azure AD'
          )
        end

        before do
          allow(Onetime::CustomDomain).to receive(:from_display_domain)
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
          allow(Onetime::CustomDomain).to receive(:from_display_domain)
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

        context 'with platform fallback allowed but AUTH_ENABLED off' do
          before do
            allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
            allow(mock_auth_config).to receive(:sso_enabled?).and_return(true)
            allow(mock_auth_config).to receive(:sso_providers).and_return([
              { 'route_name' => 'google', 'display_name' => 'Google' },
            ])
            allow(OT).to receive(:conf).and_return(
              { 'site' => { 'authentication' => { 'enabled' => false } } }
            )
          end

          it 'returns disabled SSO instead of platform fallback' do
            result = described_class.build_sso_config(custom_domain_view_vars)

            expect(result).to eq({ 'enabled' => false, 'providers' => [] })
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
            domain_id: domain_id,
            enabled?: true,
            provider_type: 'entra_id',
            display_name: 'Acme Corp Entra',
            platform_route_name: 'entra',
            enforce_sso_only?: false
          )
        end

        before do
          allow(Onetime::CustomDomain).to receive(:from_display_domain)
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
          allow(Onetime::CustomDomain).to receive(:from_display_domain)
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

  describe '.sso_available?' do
    let(:custom_domain_obj) do
      instance_double(Onetime::CustomDomain, identifier: domain_id)
    end

    let(:custom_domain_view_vars) do
      base_view_vars.merge(
        'domain_strategy' => :custom,
        'display_domain' => custom_display_domain
      )
    end

    before do
      allow(Onetime::CustomDomain).to receive(:from_display_domain).and_return(nil)
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with(custom_display_domain)
        .and_return(custom_domain_obj)
      allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
        .with(domain_id)
        .and_return(nil)
      allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
      allow(mock_auth_config).to receive(:sso_enabled?).and_return(true)
      allow(mock_auth_config).to receive(:sso_providers).and_return([
        { 'route_name' => 'oidc', 'display_name' => 'Platform SSO' },
      ])
    end

    context 'when AUTH_ENABLED is on' do
      it 'returns true via platform fallback on a custom domain' do
        expect(described_class.sso_available?(custom_domain_view_vars)).to be true
      end
    end

    context 'when AUTH_ENABLED is off' do
      before do
        allow(OT).to receive(:conf).and_return(
          { 'site' => { 'authentication' => { 'enabled' => false } } }
        )
      end

      it 'returns false on a custom domain with fallback allowed' do
        expect(described_class.sso_available?(custom_domain_view_vars)).to be false
      end

      it 'returns false on the canonical domain' do
        expect(described_class.sso_available?(base_view_vars)).to be false
      end
    end
  end

  describe '.resolve_signin' do
    let(:custom_domain_obj) do
      instance_double(Onetime::CustomDomain, identifier: domain_id)
    end

    let(:custom_domain_view_vars) do
      base_view_vars.merge(
        'domain_strategy' => :custom,
        'display_domain' => custom_display_domain
      )
    end

    before do
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with(custom_display_domain)
        .and_return(custom_domain_obj)
      allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
        .with(domain_id)
        .and_return(nil)
      allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
        .with(domain_id)
        .and_return(nil)
      allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
      allow(mock_auth_config).to receive(:sso_enabled?).and_return(true)
      allow(mock_auth_config).to receive(:sso_providers).and_return([
        { 'route_name' => 'oidc', 'display_name' => 'Platform SSO' },
      ])
    end

    context 'when AUTH_ENABLED is on' do
      it 'keeps signin available via platform SSO fallback' do
        expect(described_class.resolve_signin(custom_domain_view_vars)).to be true
      end
    end

    context 'when AUTH_ENABLED is off' do
      before do
        allow(OT).to receive(:conf).and_return(
          { 'site' => { 'authentication' => { 'enabled' => false } } }
        )
      end

      it 'no longer reports signin available via SSO' do
        expect(described_class.resolve_signin(custom_domain_view_vars)).to be false
      end
    end
  end

  describe '.resolve_restrict_to' do
    let(:custom_domain_obj) do
      instance_double(Onetime::CustomDomain, identifier: domain_id)
    end

    let(:custom_domain_view_vars) do
      base_view_vars.merge(
        'domain_strategy' => :custom,
        'display_domain' => custom_display_domain
      )
    end

    before do
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with(custom_display_domain)
        .and_return(custom_domain_obj)
      # Canonical requests resolve no domain — stubbed so the canonical
      # characterization examples below do not depend on datastore state.
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .with(canonical_domain)
        .and_return(nil)
      allow(Onetime::CustomDomain::SsoConfig).to receive(:find_by_domain_id)
        .with(domain_id)
        .and_return(nil)
      allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
        .with(domain_id)
        .and_return(nil)
      allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(true)
      allow(mock_auth_config).to receive(:sso_enabled?).and_return(true)
      allow(mock_auth_config).to receive(:sso_providers).and_return([
        { 'route_name' => 'oidc', 'display_name' => 'Platform SSO' },
      ])
    end

    context 'when AUTH_ENABLED is on' do
      it "pins restrict_to to 'sso' on a custom domain with SSO available" do
        expect(described_class.resolve_restrict_to(custom_domain_view_vars)).to eq('sso')
      end
    end

    context 'when AUTH_ENABLED is off' do
      before do
        allow(OT).to receive(:conf).and_return(
          { 'site' => { 'authentication' => { 'enabled' => false } } }
        )
      end

      it "does not pin restrict_to to 'sso'" do
        result = described_class.resolve_restrict_to(custom_domain_view_vars)
        expect(result).to be_nil
      end
    end

    # An ENABLED domain SigninConfig replaces the global restrict_to — except
    # for 'webauthn', which can never be honored on a custom domain (passkey
    # rp_id is host-scoped, so canonical-host credentials cannot assert here;
    # a passkey-only page would lock every visitor out). Persisted 'webauthn'
    # resolves to the fail-closed :unavailable state
    # (ADR-034#degradation-is-fail-closed). The legacy
    # scalar remains null — NOT the tenant 'sso' pin — while the companion
    # effective_restrict_to field carries the explicit resolver state.
    context 'with an enabled domain SigninConfig' do
      # These examples are about which restriction the serializer REPORTS, so
      # the host's capabilities are stood up as available: AUTH_SIGNIN on
      # (the file-level stub carries only the master switch) and the
      # email-auth feature on. Without them the fail-closed derivation below
      # (ADR-034#degradation-is-fail-closed) correctly
      # answers :unavailable for every method and the examples stop testing
      # what they are named for.
      before do
        allow(OT).to receive(:conf).and_return(
          { 'site' => { 'authentication' => { 'enabled' => true, 'signin' => true } } }
        )
        allow(mock_auth_config).to receive(:email_auth_enabled?).and_return(true)
      end

      # The resolver DERIVES whether the named method can run on this host
      # (ADR-034#degradation-is-fail-closed domain half), so the double must
      # answer the capability questions
      # restriction_available_for_custom_domain? asks: the domain's
      # own opt-ins, and its identifier for the SSO ladder.
      def stub_signin_config(restrict_to)
        config = instance_double(
          Onetime::CustomDomain::SigninConfig,
          domain_id: domain_id,
          enabled?: true,
          signin_enabled?: true,
          email_auth_enabled?: true,
          sso_enabled?: true,
          restrict_to: restrict_to
        )
        allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
          .with(domain_id)
          .and_return(config)
      end

      it "keeps persisted restrict_to='webauthn' null in the legacy scalar projection" do
        stub_signin_config('webauthn')

        expect(described_class.resolve_restrict_to(custom_domain_view_vars)).to be_nil
      end

      it 'passes other persisted restrictions through verbatim' do
        stub_signin_config('password')
        expect(described_class.resolve_restrict_to(custom_domain_view_vars)).to eq('password')

        stub_signin_config('email_auth')
        expect(described_class.resolve_restrict_to(custom_domain_view_vars)).to eq('email_auth')

        stub_signin_config('sso')
        expect(described_class.resolve_restrict_to(custom_domain_view_vars)).to eq('sso')
      end

      it 'keeps an unrestricted enabled config at nil' do
        stub_signin_config(nil)

        expect(described_class.resolve_restrict_to(custom_domain_view_vars)).to be_nil
      end

      # ADR-034#resolution-is-model-owned / #degradation-is-fail-closed: the
      # legacy scalar is string-or-null, while the explicit resolver wire
      # object preserves "unavailable" for display consumers.
      it "reports 'webauthn' as unavailable on the resolution object" do
        stub_signin_config('webauthn')

        resolution = described_class.restrict_to_resolution(custom_domain_view_vars)

        expect(resolution).to be_unavailable
        expect(resolution).not_to be_unrestricted
        expect(resolution.restrict_to).to eq('webauthn')
        expect(resolution.allows?('password')).to be false
        expect(resolution.allows?('webauthn')).to be false
      end

      it 'serializes the unavailable resolution into bootstrap features' do
        stub_signin_config('webauthn')

        features = described_class.build_feature_flags(custom_domain_view_vars)

        expect(features['restrict_to']).to be_nil
        expect(features['effective_restrict_to']).to eq(
          'state' => 'unavailable',
          'restrict_to' => 'webauthn',
          'source' => 'domain'
        )
      end

      it 'attributes an honored domain restriction to the domain layer' do
        stub_signin_config('password')

        resolution = described_class.restrict_to_resolution(custom_domain_view_vars)

        expect(resolution).to be_restricted
        expect(resolution.source).to eq(:domain)
        expect(resolution.allows?('password')).to be true
        expect(resolution.allows?('sso')).to be false
      end
    end

    # Characterization of the pre-extraction behavior
    # (ADR-034#resolution-is-model-owned): the
    # serializer is now a consumer of SigninConfig.resolve_restrict_to, and
    # these cases pin the wire output it produced before that refactor.
    context 'on a canonical request' do
      it 'passes the global restriction through' do
        allow(mock_auth_config).to receive(:restrict_to).and_return('password')

        expect(described_class.resolve_restrict_to(base_view_vars)).to eq('password')
      end

      it 'is nil when nothing is restricted globally' do
        allow(mock_auth_config).to receive(:restrict_to).and_return(nil)

        expect(described_class.resolve_restrict_to(base_view_vars)).to be_nil
      end

      it 'never applies the tenant SSO pin' do
        allow(mock_auth_config).to receive(:restrict_to).and_return(nil)
        allow(described_class).to receive(:sso_available?).and_return(true)

        expect(described_class.resolve_restrict_to(base_view_vars)).to be_nil
      end
    end

    context 'with a domain SigninConfig whose master switch is off' do
      before do
        config = instance_double(
          Onetime::CustomDomain::SigninConfig,
          enabled?: false,
          restrict_to: 'password'
        )
        allow(Onetime::CustomDomain::SigninConfig).to receive(:find_by_domain_id)
          .with(domain_id)
          .and_return(config)
      end

      it 'ignores the domain restriction and takes the tenant SSO pin' do
        expect(described_class.resolve_restrict_to(custom_domain_view_vars)).to eq('sso')
      end

      # The inherited global restriction still stands (the domain's own
      # restriction is ignored while its master switch is off), but it names a
      # method this host cannot run: email-auth defaults OFF on a custom domain
      # and this config never opted in. So the page reports :unavailable — the
      # same answer Auth::RestrictTo gives, which 404s those routes (#4139).
      # The legacy string-or-null scalar cannot express :unavailable and
      # projects to nil; effective_restrict_to carries the real state.
      it 'inherits the global restriction and fails it closed for this host' do
        allow(mock_auth_config).to receive(:sso_enabled?).and_return(false)
        allow(mock_auth_config).to receive(:allow_platform_fallback_for_tenants?).and_return(false)
        allow(mock_auth_config).to receive(:restrict_to).and_return('email_auth')

        resolution = described_class.restrict_to_resolution(custom_domain_view_vars)

        expect(resolution).to be_unavailable
        expect(resolution.restrict_to).to eq('email_auth')
        expect(resolution.source).to eq(:global)
        expect(described_class.resolve_restrict_to(custom_domain_view_vars)).to be_nil
      end
    end

    # The point of ADR-034#resolution-is-model-owned: one owner. If this
    # delegation is ever inlined again the three gates drift apart, which is
    # the failure mode that decision exists to prevent.
    it 'delegates resolution to the model resolver' do
      allow(mock_auth_config).to receive(:restrict_to).and_return('password')

      expect(Onetime::CustomDomain::SigninConfig).to receive(:resolve_restrict_to)
        .with('password', nil, available: true)
        .and_call_original

      expect(described_class.resolve_restrict_to(base_view_vars)).to eq('password')
    end

    # ADR-034#degradation-is-fail-closed, post-boot half (#4139). Before
    # this, the serializer was the one consumer that never applied
    # restrict_to_available? at all: the route
    # gate had already gone dark while this page still rendered the restricted
    # method's form. The flag now rides into the resolver, so display and gate
    # degrade together.
    context 'when the global restriction became unavailable after boot' do
      before do
        allow(mock_auth_config).to receive(:restrict_to).and_return('password')
        allow(mock_auth_config).to receive(:restrict_to_available?).and_return(false)
      end

      it 'hands the availability flag to the resolver' do
        expect(Onetime::CustomDomain::SigninConfig).to receive(:resolve_restrict_to)
          .with('password', nil, available: false)
          .and_call_original

        described_class.restrict_to_resolution(base_view_vars)
      end

      it 'resolves :unavailable rather than the restricted method' do
        resolution = described_class.restrict_to_resolution(base_view_vars)

        expect(resolution).to be_unavailable
        expect(resolution.restrict_to).to eq('password')
        expect(resolution.source).to eq(:global)
        expect(resolution.allows?('password')).to be false
      end

      it 'never widens to standard mode when nothing is restricted' do
        allow(mock_auth_config).to receive(:restrict_to).and_return(nil)

        resolution = described_class.restrict_to_resolution(base_view_vars)

        expect(resolution).to be_unrestricted
        expect(resolution.allows?('password')).to be true
      end

      it 'does not apply to the tenant SSO pin, which is a host property' do
        # The pin is not the operator's configured restriction, so AuthConfig's
        # availability verdict about that restriction must not reach it.
        expect(described_class.resolve_restrict_to(custom_domain_view_vars)).to eq('sso')
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

      context 'when incoming_secrets_enabled is true but install-level incoming.enabled is false' do
        let(:view_vars_with_incoming) do
          base_view_vars.merge(
            'features' => base_view_vars['features'].merge(
              'incoming' => { 'enabled' => false },
              'organizations' => { 'enabled' => false, 'incoming_secrets_enabled' => true }
            )
          )
        end

        it 'returns incoming_secrets_enabled as true (install flag gates the canonical domain only, not the per-domain config surface)' do
          result = described_class.build_feature_flags(view_vars_with_incoming)

          expect(result['organizations']['incoming_secrets_enabled']).to be true
        end
      end

      context 'when both incoming_secrets_enabled and install-level incoming.enabled are true' do
        let(:view_vars_with_incoming) do
          base_view_vars.merge(
            'features' => base_view_vars['features'].merge(
              'incoming' => { 'enabled' => true },
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
              'incoming' => { 'enabled' => true },
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
              'incoming' => { 'enabled' => true },
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

      # audit_logs_enabled inverts the sibling default: it is an opt-out
      # exclusion (ORGS_AUDIT_LOGS_ENABLED=false), so a missing key — e.g.
      # an install running an older config file — must still read as true.
      describe 'audit_logs_enabled (default-true contract)' do
        context 'when the key is absent (older config file)' do
          it 'defaults to true, unlike sibling flags' do
            result = described_class.build_feature_flags(base_view_vars)

            expect(result['organizations']['audit_logs_enabled']).to be true
          end
        end

        context 'when explicitly true' do
          let(:view_vars_with_audit_logs) do
            base_view_vars.merge(
              'features' => base_view_vars['features'].merge(
                'organizations' => { 'enabled' => true, 'audit_logs_enabled' => true }
              )
            )
          end

          it 'includes audit_logs_enabled as true' do
            result = described_class.build_feature_flags(view_vars_with_audit_logs)

            expect(result['organizations']['audit_logs_enabled']).to be true
          end
        end

        context 'when explicitly false (operator opt-out)' do
          let(:view_vars_without_audit_logs) do
            base_view_vars.merge(
              'features' => base_view_vars['features'].merge(
                'organizations' => { 'enabled' => true, 'audit_logs_enabled' => false }
              )
            )
          end

          it 'includes audit_logs_enabled as false' do
            result = described_class.build_feature_flags(view_vars_without_audit_logs)

            expect(result['organizations']['audit_logs_enabled']).to be false
          end

          it 'does not affect other organization flags' do
            result = described_class.build_feature_flags(view_vars_without_audit_logs)
            orgs = result['organizations']

            expect(orgs['enabled']).to be true
            expect(orgs['sso_enabled']).to be false
            expect(orgs['custom_mail_enabled']).to be false
            expect(orgs['incoming_secrets_enabled']).to be false
          end
        end

        # Defense-in-depth for hand-edited config files: a YAML loader (or a
        # quoted value) can deliver the string 'false' where the shipped ERB
        # emits a real boolean. Ruby's 'false' != false is true, so a raw
        # comparison would silently re-enable the flag against operator intent.
        context "when the string 'false' (hand-edited config)" do
          let(:view_vars_string_false) do
            base_view_vars.merge(
              'features' => base_view_vars['features'].merge(
                'organizations' => { 'enabled' => true, 'audit_logs_enabled' => 'false' }
              )
            )
          end

          it 'treats it as disabled' do
            result = described_class.build_feature_flags(view_vars_string_false)

            expect(result['organizations']['audit_logs_enabled']).to be false
          end
        end

        context "when the string 'true'" do
          let(:view_vars_string_true) do
            base_view_vars.merge(
              'features' => base_view_vars['features'].merge(
                'organizations' => { 'enabled' => true, 'audit_logs_enabled' => 'true' }
              )
            )
          end

          it 'stays enabled' do
            result = described_class.build_feature_flags(view_vars_string_true)

            expect(result['organizations']['audit_logs_enabled']).to be true
          end
        end

        context 'when nil (key present, no value)' do
          let(:view_vars_nil_audit_logs) do
            base_view_vars.merge(
              'features' => base_view_vars['features'].merge(
                'organizations' => { 'enabled' => true, 'audit_logs_enabled' => nil }
              )
            )
          end

          it 'stays enabled (default-true contract)' do
            result = described_class.build_feature_flags(view_vars_nil_audit_logs)

            expect(result['organizations']['audit_logs_enabled']).to be true
          end
        end
      end

      # secret_activity is the data-existence axis (#3990): whether events are
      # recorded at all (SECRET_ACTIVITY_COLLECT) and how many are retained
      # (SECRET_ACTIVITY_MAX_EVENTS). Same default-true / opt-out contract as
      # audit_logs_enabled above, which remains the separate UI-exposure axis.
      describe 'secret_activity (collection axis + retention cap)' do
        def view_vars_with_secret_activity(secret_activity)
          base_view_vars.merge(
            'features' => base_view_vars['features'].merge('secret_activity' => secret_activity)
          )
        end

        context 'when the key is absent (older config file)' do
          it 'defaults to collect_enabled true with the 10,000 cap' do
            result = described_class.build_feature_flags(base_view_vars)

            expect(result['secret_activity']).to eq(
              'collect_enabled' => true,
              'max_events' => 10_000,
              'geo_country_enabled' => false,
            )
          end
        end

        # geo_country_enabled is the DEFAULT-OFF (opt-in) inverse of the flags
        # above: only an explicit true enables the org Secret Activity country
        # column, gated pending counsel review (#3989; ADR-021 Decision 4).
        describe 'geo_country_enabled (default-OFF opt-in contract)' do
          it 'is false when the key is absent' do
            result = described_class.build_feature_flags(base_view_vars)

            expect(result['secret_activity']['geo_country_enabled']).to be false
          end

          it 'is true only when explicitly true' do
            result = described_class.build_feature_flags(
              view_vars_with_secret_activity('geo_country_enabled' => true)
            )

            expect(result['secret_activity']['geo_country_enabled']).to be true
          end

          it "enables on the string 'true' (ERB-stringified config)" do
            result = described_class.build_feature_flags(
              view_vars_with_secret_activity('geo_country_enabled' => 'true')
            )

            expect(result['secret_activity']['geo_country_enabled']).to be true
          end

          it 'stays false for explicit false' do
            result = described_class.build_feature_flags(
              view_vars_with_secret_activity('geo_country_enabled' => false)
            )

            expect(result['secret_activity']['geo_country_enabled']).to be false
          end
        end

        describe 'collect_enabled (default-true contract)' do
          it 'is true when explicitly true' do
            result = described_class.build_feature_flags(
              view_vars_with_secret_activity('collect' => true)
            )

            expect(result['secret_activity']['collect_enabled']).to be true
          end

          it 'is false when explicitly false (operator opt-out)' do
            result = described_class.build_feature_flags(
              view_vars_with_secret_activity('collect' => false)
            )

            expect(result['secret_activity']['collect_enabled']).to be false
          end

          # Same hand-edited-config defense as audit_logs_enabled: the string
          # 'false' must pause the banner-facing flag, or the UI would say
          # "recording" while the model (which shares the string-compare
          # idiom) had already paused.
          it "treats the string 'false' as disabled (hand-edited config)" do
            result = described_class.build_feature_flags(
              view_vars_with_secret_activity('collect' => 'false')
            )

            expect(result['secret_activity']['collect_enabled']).to be false
          end

          it "stays enabled for the string 'true'" do
            result = described_class.build_feature_flags(
              view_vars_with_secret_activity('collect' => 'true')
            )

            expect(result['secret_activity']['collect_enabled']).to be true
          end

          it 'stays enabled when nil (key present, no value)' do
            result = described_class.build_feature_flags(
              view_vars_with_secret_activity('collect' => nil)
            )

            expect(result['secret_activity']['collect_enabled']).to be true
          end
        end

        # max_events mirrors the boot-time coercion + clamp (SecretActivity
        # .configure!) so the UI never advertises a cap the backend ignored.
        describe 'max_events (coercion + floor clamp parity with boot)' do
          it 'passes through a configured cap above the floor' do
            result = described_class.build_feature_flags(
              view_vars_with_secret_activity('max_events' => 5_000)
            )

            expect(result['secret_activity']['max_events']).to eq(5_000)
          end

          it 'clamps below-floor values up to MIN_MAX_EVENTS (floor 100)' do
            result = described_class.build_feature_flags(
              view_vars_with_secret_activity('max_events' => 5)
            )

            expect(result['secret_activity']['max_events'])
              .to eq(Onetime::Organization::Features::SecretActivity::MIN_MAX_EVENTS)
          end

          it 'coerces an integer-shaped string (ENV/hand-edited YAML)' do
            result = described_class.build_feature_flags(
              view_vars_with_secret_activity('max_events' => '500')
            )

            expect(result['secret_activity']['max_events']).to eq(500)
          end

          it 'falls back to the 10,000 default for non-numeric garbage' do
            result = described_class.build_feature_flags(
              view_vars_with_secret_activity('max_events' => 'unbounded')
            )

            expect(result['secret_activity']['max_events']).to eq(10_000)
          end

          it 'falls back to the 10,000 default when nil' do
            result = described_class.build_feature_flags(
              view_vars_with_secret_activity('max_events' => nil)
            )

            expect(result['secret_activity']['max_events']).to eq(10_000)
          end
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
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
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
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
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

    context 'when CustomDomain lookup fails (Redis error)' do
      before do
        allow(OT).to receive(:le)
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .and_raise(Redis::ConnectionError.new('Connection refused'))
      end

      it 'returns DOMAIN_READ_FAILED sentinel (#4157)' do
        vars = base_view_vars.merge(
          'domain_strategy' => :custom,
          'display_domain' => 'tenant.example.com'
        )
        result = described_class.resolve_domain_id(vars)
        expect(result).to eq(described_class::DOMAIN_READ_FAILED)
      end

      # DomainStrategy publishes display_domain unconditionally (canonical
      # fallback), so the canonical render reaches this same read — and must
      # not be told the tenant policy is unknown, which would strip its own
      # sign-in affordances during a blip.
      it 'returns nil, not the sentinel, on an operator host' do
        vars = base_view_vars.merge(
          'domain_strategy' => :canonical,
          'display_domain' => canonical_domain
        )
        expect(described_class.resolve_domain_id(vars)).to be_nil
      end
    end
  end

  describe 'tri-state domain resolution (#4157)' do
    let(:custom_domain_view_vars) do
      base_view_vars.merge(
        'domain_strategy' => :custom,
        'display_domain' => custom_display_domain,
        'site' => { 'authentication' => { 'enabled' => true, 'signin' => true } },
      )
    end

    before do
      allow(Onetime::CustomDomain).to receive(:from_display_domain)
        .and_raise(Redis::ConnectionError.new('Connection refused'))
      allow(mock_auth_config).to receive(:email_auth_enabled?).and_return(true)
      allow(mock_auth_config).to receive(:restrict_to).and_return(nil)
    end

    it 'resolve_signin returns false on read failure (narrowest surface)' do
      result = described_class.resolve_signin(custom_domain_view_vars)
      expect(result).to be(false)
    end

    it 'resolve_email_auth returns false on read failure' do
      result = described_class.resolve_email_auth(custom_domain_view_vars)
      expect(result).to be(false)
    end

    it 'restrict_to_resolution returns :unavailable on read failure' do
      result = described_class.restrict_to_resolution(custom_domain_view_vars)
      expect(result.unavailable?).to be(true)
      expect(result.source).to eq(:domain_read_failed)
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
      config = build_domain_sso_config(:oidc)
      allow(config).to receive(:display_name).and_return(nil)

      result = described_class.build_tenant_sso_response(config)

      expect(result['providers'][0]['display_name']).to eq('')
    end
  end
end

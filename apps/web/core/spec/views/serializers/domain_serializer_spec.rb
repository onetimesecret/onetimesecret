# apps/web/core/spec/views/serializers/domain_serializer_spec.rb
#
# frozen_string_literal: true

# Unit tests for DomainSerializer including domain_context persistence
#
# Run with:
#   source .env.test && bundle exec rspec apps/web/core/spec/views/serializers/domain_serializer_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../views/serializers'

RSpec.describe Core::Views::DomainSerializer do
  let(:canonical_domain) { 'onetimesecret.com' }

  let(:customer) do
    instance_double(
      Onetime::Customer,
      custom_domains_list: []
    )
  end

  let(:session) do
    {
      'csrf' => 'test-csrf-token',
      'domain_context' => nil,
    }
  end

  let(:view_vars) do
    {
      'authenticated' => false,
      'cust' => customer,
      'sess' => session,
      'features' => { 'domains' => { 'enabled' => false } },
      'domain_strategy' => :canonical,
      'display_domain' => canonical_domain,
    }
  end

  before do
    allow(Onetime::Middleware::DomainStrategy).to receive(:canonical_domain).and_return(canonical_domain)
  end

  describe '.output_template' do
    it 'includes domain_context field' do
      template = described_class.output_template
      expect(template).to have_key('domain_context')
    end

    it 'includes all expected domain fields' do
      template = described_class.output_template
      expected_keys = %w[
        canonical_domain
        custom_domains
        display_domain
        domain_branding
        domain_id
        domain_locale
        domain_logo
        domain_context
        domain_strategy
        link_domains
      ]
      expected_keys.each do |key|
        expect(template).to have_key(key), "Expected template to include '#{key}'"
      end
    end

    # The template entry is load-bearing and NOT covered by the .serialize
    # specs below: serialize writes output['link_domains'] onto the template
    # hash, so it is present there either way. SerializerRegistry.run strips
    # every key the template does not declare, so losing this entry drops the
    # field from the bootstrap payload with nothing else going red (#4063).
    it 'declares link_domains so SerializerRegistry does not strip it' do
      expect(described_class.output_template).to have_key('link_domains')
    end

    it 'defaults link_domains to [] rather than nil' do
      # The frontend types this as z.array(z.string()).default([]), and a Zod
      # default only fires for a MISSING key, never an explicit null.
      expect(described_class.output_template['link_domains']).to eq([])
    end
  end

  describe '.serialize' do
    context 'when user is not authenticated' do
      let(:view_vars) do
        {
          'authenticated' => false,
          'cust' => customer,
          'sess' => session,
          'features' => { 'domains' => { 'enabled' => false } },
          'domain_strategy' => :canonical,
          'display_domain' => canonical_domain,
        }
      end

      it 'returns nil for domain_context' do
        result = described_class.serialize(view_vars)
        expect(result['domain_context']).to be_nil
      end
    end

    context 'when user is authenticated' do
      let(:view_vars) do
        {
          'authenticated' => true,
          'cust' => customer,
          'sess' => session,
          'features' => { 'domains' => { 'enabled' => false } },
          'domain_strategy' => :canonical,
          'display_domain' => canonical_domain,
        }
      end

      it 'returns domain_context from session' do
        session['domain_context'] = 'custom.example.com'
        result = described_class.serialize(view_vars)
        expect(result['domain_context']).to eq('custom.example.com')
      end

      it 'returns nil when domain_context is not set in session' do
        session['domain_context'] = nil
        result = described_class.serialize(view_vars)
        expect(result['domain_context']).to be_nil
      end
    end

    context 'when session is missing' do
      let(:view_vars) do
        {
          'authenticated' => true,
          'cust' => customer,
          'sess' => nil,
          'features' => { 'domains' => { 'enabled' => false } },
          'domain_strategy' => :canonical,
          'display_domain' => canonical_domain,
        }
      end

      it 'handles missing session gracefully' do
        result = described_class.serialize(view_vars)
        expect(result['domain_context']).to be_nil
      end
    end

    it 'returns canonical_domain' do
      result = described_class.serialize(view_vars)
      expect(result['canonical_domain']).to eq(canonical_domain)
    end

    it 'returns display_domain' do
      result = described_class.serialize(view_vars)
      expect(result['display_domain']).to eq(canonical_domain)
    end

    it 'returns domain_strategy' do
      result = described_class.serialize(view_vars)
      expect(result['domain_strategy']).to eq(:canonical)
    end

    # ======================================================================
    # link_domains — the resolved link-picker pool (#4063)
    #
    # Resolution happens SERVER-side: the payload always carries a concrete
    # pool, and the frontend must never re-derive unset => [canonical]. These
    # drive the real DomainStrategy through initialize_from_config rather than
    # stubbing the reader, so what is pinned is the value the browser actually
    # receives for a given operator config.
    # ======================================================================
    describe 'link_domains (#4063)' do
      let(:site_host)   { 'app.example.net' }
      let(:link_host)   { 'ge-abcd123.eu.otshosted.com' }
      let(:pool_member) { 'short.example.com' }

      # DomainStrategy holds its config in class instance variables; save and
      # restore all of them so this cannot leak into the rest of the suite.
      around do |example|
        ivars = %i[
          @canonical_domain @domains_enabled @canonical_domains
          @canonical_domains_parsed @anchor_domains_parsed @link_domains
          @domain_context_enabled
        ]
        saved = ivars.to_h do |ivar|
          [ivar, Onetime::Middleware::DomainStrategy.instance_variable_get(ivar)]
        end

        begin
          example.run
        ensure
          saved.each do |ivar, value|
            Onetime::Middleware::DomainStrategy.instance_variable_set(ivar, value)
          end
        end
      end

      # The outer before stubs canonical_domain; here the real resolved value
      # is the point of the assertion.
      before do
        allow(Onetime::Middleware::DomainStrategy).to receive(:canonical_domain).and_call_original
      end

      def boot_domain_strategy(domains_config)
        allow(OT).to receive(:conf).and_return({
          'site' => { 'host' => site_host },
          'features' => { 'domains' => domains_config },
        })
        Onetime::Middleware::DomainStrategy.initialize_from_config(domains_config)
      end

      context 'when LINK_DOMAINS is unset' do
        before { boot_domain_strategy('enabled' => true, 'default' => link_host) }

        it 'emits the canonical domain as the only pool member' do
          result = described_class.serialize(view_vars)
          expect(result['link_domains']).to eq([link_host])
        end

        it 'agrees with canonical_domain in the same payload' do
          result = described_class.serialize(view_vars)
          expect(result['link_domains']).to eq([result['canonical_domain']])
        end
      end

      context 'when LINK_DOMAINS names hosts' do
        before do
          boot_domain_strategy(
            'enabled' => true,
            'default' => link_host,
            'link_domains' => [pool_member, 'go.acme.com'],
          )
        end

        it 'emits the configured pool verbatim, in order' do
          result = described_class.serialize(view_vars)
          expect(result['link_domains']).to eq([pool_member, 'go.acme.com'])
        end

        it 'leaves canonical_domain unchanged and out of the pool' do
          # The whole feature: the internal platform host keeps serving and
          # stays the CNAME target, but is not offered in the picker.
          result = described_class.serialize(view_vars)
          expect(result['canonical_domain']).to eq(link_host)
          expect(result['link_domains']).not_to include(link_host)
        end
      end

      context 'when features.domains.enabled is false' do
        before { boot_domain_strategy('enabled' => false) }

        it 'still emits the key — the picker needs a pool in every mode' do
          result = described_class.serialize(view_vars)
          expect(result).to have_key('link_domains')
          expect(result['link_domains']).to eq([site_host])
        end

        it 'ignores a link pool configured while the feature is off' do
          boot_domain_strategy('enabled' => false, 'link_domains' => [pool_member])

          result = described_class.serialize(view_vars)
          expect(result['link_domains']).to eq([site_host])
        end
      end

      context 'before DomainStrategy has been configured (pre-boot / reset!)' do
        before { Onetime::Middleware::DomainStrategy.reset! }

        it 'emits an empty array rather than null' do
          result = described_class.serialize(view_vars)
          expect(result['link_domains']).to eq([])
        end
      end

      # The registry is the real output boundary: it drops any key the
      # serializer's output_template does not declare.
      it 'survives the SerializerRegistry output-boundary strip' do
        boot_domain_strategy(
          'enabled' => true,
          'default' => link_host,
          'link_domains' => [pool_member],
        )

        result = Core::Views::SerializerRegistry.run([described_class], view_vars)
        expect(result['link_domains']).to eq([pool_member])
      end
    end

    context 'when domain_strategy is :custom' do
      # These tests verify that domain_branding boolean fields are native JSON booleans,
      # not string-encoded values like "true" or "false".
      #
      # Background: Redis hgetall returns all values as strings. The serializer must
      # coerce boolean fields to native booleans for frontend V3 schema compatibility.
      #
      # Boolean fields to test:
      #   - button_text_light
      #   - allow_public_homepage
      #   - allow_public_api
      #   - passphrase_required
      #   - notify_enabled

      let(:custom_display_domain) { 'secrets.example.com' }

      # Simulate Redis hgetall returning string values (the actual bug scenario)
      let(:brand_hash_from_redis) do
        {
          'primary_color' => '#FF5733',
          'font_family' => 'sans',
          'corner_style' => 'rounded',
          'locale' => 'en',
          'button_text_light' => 'true',
          'allow_public_homepage' => 'false',
          'allow_public_api' => 'true',
          'passphrase_required' => 'false',
          'notify_enabled' => 'true',
        }
      end

      let(:brand_double) do
        instance_double('Familia::Horreum::ClassMethods::Hashkey', hgetall: brand_hash_from_redis)
      end

      let(:logo_double) do
        instance_double('Familia::Horreum::ClassMethods::Hashkey', :[] => nil)
      end

      let(:custom_domain) do
        instance_double(
          Onetime::CustomDomain,
          domainid: 'domain123',
          extid: 'ext456',
          identifier: 'domain123',
          display_domain: custom_display_domain,
          brand: brand_double,
          logo: logo_double
        )
      end

      let(:custom_domain_view_vars) do
        {
          'authenticated' => false,
          'cust' => customer,
          'sess' => session,
          'features' => { 'domains' => { 'enabled' => false } },
          'domain_strategy' => :custom,
          'display_domain' => custom_display_domain,
        }
      end

      before do
        allow(Onetime::CustomDomain).to receive(:from_display_domain)
          .with(custom_display_domain)
          .and_return(custom_domain)
        allow(Onetime::CustomDomain::HomepageConfig).to receive(:find_by_domain_id)
          .with('domain123')
          .and_return(nil)
      end

      describe 'domain_branding boolean field types' do
        # These tests should FAIL initially (TDD red phase) because the current
        # implementation at domain_serializer.rb:42 does:
        #   output['domain_branding'] = (custom_domain&.brand&.hgetall || {}).to_h
        # which passes Redis strings directly without coercion.

        it 'returns button_text_light as a native boolean, not a string' do
          result = described_class.serialize(custom_domain_view_vars)
          branding = result['domain_branding']

          expect(branding['button_text_light']).to be(true),
            "Expected button_text_light to be boolean true, got #{branding['button_text_light'].inspect} (#{branding['button_text_light'].class})"
        end

        it 'strips legacy allow_public_homepage from branding (#3026)' do
          # Post-#3026, HomepageConfig is the source of truth; legacy
          # brand[allow_public_homepage] is filtered to prevent the dual
          # source of truth from leaking through to the frontend.
          result = described_class.serialize(custom_domain_view_vars)
          branding = result['domain_branding']

          expect(branding).not_to have_key('allow_public_homepage')
        end

        it 'strips legacy allow_public_api from branding (#3026)' do
          # Post-#3026, ApiConfig is the source of truth; legacy
          # brand[allow_public_api] is filtered for the same reason.
          result = described_class.serialize(custom_domain_view_vars)
          branding = result['domain_branding']

          expect(branding).not_to have_key('allow_public_api')
        end

        it 'returns passphrase_required as a native boolean, not a string' do
          result = described_class.serialize(custom_domain_view_vars)
          branding = result['domain_branding']

          expect(branding['passphrase_required']).to be(false),
            "Expected passphrase_required to be boolean false, got #{branding['passphrase_required'].inspect} (#{branding['passphrase_required'].class})"
        end

        it 'returns notify_enabled as a native boolean, not a string' do
          result = described_class.serialize(custom_domain_view_vars)
          branding = result['domain_branding']

          expect(branding['notify_enabled']).to be(true),
            "Expected notify_enabled to be boolean true, got #{branding['notify_enabled'].inspect} (#{branding['notify_enabled'].class})"
        end

        it 'preserves non-boolean fields as strings' do
          result = described_class.serialize(custom_domain_view_vars)
          branding = result['domain_branding']

          # String fields should remain strings
          expect(branding['primary_color']).to eq('#FF5733')
          expect(branding['font_family']).to eq('sans')
          expect(branding['corner_style']).to eq('rounded')
          expect(branding['locale']).to eq('en')
        end
      end

      describe 'homepage_config secrets_mode serialization' do
        # The bootstrap payload is the read-path invariant for the homepage
        # secrets_mode feature. The availability matrix itself (feature flag,
        # site.secret, IncomingConfig readiness, entitlement) lives on
        # HomepageConfig#effectively_enabled? — the single source of truth
        # shared with the homepage-config API responses — and is covered by
        # spec/unit/onetime/models/custom_domain/homepage_config_effective_spec.rb.
        # Here we pin the delegation: `enabled` carries the EFFECTIVE value
        # while the stored secrets_mode is preserved so intent survives a
        # downgrade.

        let(:homepage_config) do
          instance_double(
            Onetime::CustomDomain::HomepageConfig,
            domain_id: 'domain123',
            enabled?: true,
            secrets_mode_value: 'incoming',
            signup_enabled?: false,
            signin_enabled?: false,
            disabled_homepage_variant_value: nil,
            created: 1_700_000_000,
            updated: 1_700_000_000,
          )
        end

        before do
          allow(Onetime::CustomDomain::HomepageConfig).to receive(:find_by_domain_id)
            .with('domain123')
            .and_return(homepage_config)
        end

        it 'emits the effective enablement, passing the already-loaded domain through' do
          allow(homepage_config).to receive(:effectively_enabled?)
            .with(custom_domain: custom_domain)
            .and_return(true)

          result = described_class.serialize(custom_domain_view_vars)
          expect(result['homepage_config']['enabled']).to be(true)
          expect(result['homepage_config']['secrets_mode']).to eq('incoming')
        end

        it 'preserves the stored secrets_mode through a downgrade so intent survives' do
          allow(homepage_config).to receive(:effectively_enabled?)
            .with(custom_domain: custom_domain)
            .and_return(false)

          result = described_class.serialize(custom_domain_view_vars)
          expect(result['homepage_config']['enabled']).to be(false)
          expect(result['homepage_config']['secrets_mode']).to eq('incoming')
        end
      end

      describe 'domain_branding with mixed boolean representations' do
        # Test that the coercion handles various boolean representations

        context 'when Redis returns actual boolean values (from JSON deserialization)' do
          let(:brand_hash_from_redis) do
            {
              'button_text_light' => true,
              'notify_enabled' => false,
            }
          end

          it 'preserves native boolean values' do
            result = described_class.serialize(custom_domain_view_vars)
            branding = result['domain_branding']

            expect(branding['button_text_light']).to be(true)
            expect(branding['notify_enabled']).to be(false)
          end
        end

        context 'when boolean fields are missing from Redis' do
          let(:brand_hash_from_redis) do
            {
              'primary_color' => '#FF5733',
            }
          end

          it 'does not raise errors for missing boolean fields' do
            expect { described_class.serialize(custom_domain_view_vars) }.not_to raise_error
          end
        end
      end
    end
  end
end

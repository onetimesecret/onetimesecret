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
      ]
      expected_keys.each do |key|
        expect(template).to have_key(key), "Expected template to include '#{key}'"
      end
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

        it 'returns allow_public_homepage as a native boolean, not a string' do
          result = described_class.serialize(custom_domain_view_vars)
          branding = result['domain_branding']

          expect(branding['allow_public_homepage']).to be(false),
            "Expected allow_public_homepage to be boolean false, got #{branding['allow_public_homepage'].inspect} (#{branding['allow_public_homepage'].class})"
        end

        it 'returns allow_public_api as a native boolean, not a string' do
          result = described_class.serialize(custom_domain_view_vars)
          branding = result['domain_branding']

          expect(branding['allow_public_api']).to be(true),
            "Expected allow_public_api to be boolean true, got #{branding['allow_public_api'].inspect} (#{branding['allow_public_api'].class})"
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

      describe 'domain_branding with mixed boolean representations' do
        # Test that the coercion handles various boolean representations

        context 'when Redis returns actual boolean values (from JSON deserialization)' do
          let(:brand_hash_from_redis) do
            {
              'button_text_light' => true,
              'allow_public_homepage' => false,
            }
          end

          it 'preserves native boolean values' do
            result = described_class.serialize(custom_domain_view_vars)
            branding = result['domain_branding']

            expect(branding['button_text_light']).to be(true)
            expect(branding['allow_public_homepage']).to be(false)
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

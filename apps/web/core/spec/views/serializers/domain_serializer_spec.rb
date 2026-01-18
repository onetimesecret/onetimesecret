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
  end
end

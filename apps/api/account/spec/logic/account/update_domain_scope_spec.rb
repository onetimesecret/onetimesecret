# apps/api/account/spec/logic/account/update_domain_scope_spec.rb
#
# frozen_string_literal: true

# Unit tests for domain scope persistence in user sessions
#
# Run with:
#   source .env.test && bundle exec rspec apps/api/account/spec/logic/account/update_domain_scope_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'account/logic'

RSpec.describe AccountAPI::Logic::Account::UpdateDomainScope do
  let(:canonical_domain) { 'onetimesecret.com' }
  let(:custom_domain) { 'secrets.example.com' }

  let(:custom_domain_obj) do
    instance_double(
      Onetime::CustomDomain,
      display_domain: custom_domain,
      ready?: true,
      verified: true,
      resolving: true
    )
  end

  let(:customer) do
    instance_double(
      Onetime::Customer,
      objid: 'test-cust-123',
      custid: 'test-cust-123',
      anonymous?: false,
      custom_domains_list: [custom_domain_obj]
    )
  end

  let(:session) do
    {
      'csrf' => 'test-csrf-token',
      'domain_scope' => nil,
    }
  end

  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: customer,
      authenticated?: true,
      metadata: {}
    )
  end

  let(:params) { { 'domain' => custom_domain } }

  subject(:logic) do
    described_class.new(strategy_result, params)
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:conf).and_return({
      'site' => {},
      'features' => { 'domains' => { 'enabled' => true } },
    })
    allow(Onetime::Middleware::DomainStrategy).to receive(:canonical_domain).and_return(canonical_domain)
  end

  describe '#process_params' do
    it 'extracts domain from params' do
      expect(logic.new_domain_scope).to eq(custom_domain)
    end

    it 'normalizes domain to lowercase' do
      params['domain'] = 'SECRETS.EXAMPLE.COM'
      logic = described_class.new(strategy_result, params)
      expect(logic.new_domain_scope).to eq('secrets.example.com')
    end

    it 'strips whitespace from domain' do
      params['domain'] = '  secrets.example.com  '
      logic = described_class.new(strategy_result, params)
      expect(logic.new_domain_scope).to eq('secrets.example.com')
    end

    it 'stores old domain scope from session' do
      session['domain_scope'] = 'old.example.com'
      logic = described_class.new(strategy_result, params)
      expect(logic.old_domain_scope).to eq('old.example.com')
    end
  end

  describe '#raise_concerns' do
    context 'when customer is anonymous' do
      let(:customer) do
        instance_double(
          Onetime::Customer,
          objid: 'anon-123',
          anonymous?: true,
          custom_domains_list: []
        )
      end

      it 'raises Unauthorized error' do
        expect { logic.raise_concerns }.to raise_error(OT::Unauthorized, /Authentication required/)
      end
    end

    context 'when domain is missing' do
      let(:params) { { 'domain' => nil } }

      it 'raises form error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Domain is required/)
      end
    end

    context 'when domain is empty' do
      let(:params) { { 'domain' => '' } }

      it 'raises form error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Domain is required/)
      end
    end

    context 'when domain is not owned by user' do
      let(:params) { { 'domain' => 'unknown.example.com' } }

      it 'raises form error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Invalid domain/)
      end
    end

    context 'when domain is the canonical domain' do
      let(:params) { { 'domain' => canonical_domain } }

      it 'does not raise any error' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end

    context 'when domain is a valid custom domain' do
      let(:params) { { 'domain' => custom_domain } }

      it 'does not raise any error' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end
  end

  describe '#process' do
    context 'with valid custom domain' do
      it 'updates session with new domain scope' do
        logic.process
        expect(session['domain_scope']).to eq(custom_domain)
      end

      it 'returns success data with new domain scope' do
        result = logic.process
        expect(result[:domain_scope]).to eq(custom_domain)
      end

      it 'returns previous domain scope in response' do
        session['domain_scope'] = 'old.example.com'
        new_logic = described_class.new(strategy_result, params)
        result = new_logic.process
        expect(result[:previous_domain_scope]).to eq('old.example.com')
      end

      it 'marks field as modified' do
        logic.process
        expect(logic.modified?(:domain_scope)).to be true
      end

      it 'sets greenlighted to true' do
        logic.process
        expect(logic.greenlighted).to be true
      end
    end

    context 'with canonical domain' do
      let(:params) { { 'domain' => canonical_domain } }

      it 'updates session with canonical domain' do
        logic.process
        expect(session['domain_scope']).to eq(canonical_domain)
      end

      it 'returns success data' do
        result = logic.process
        expect(result[:domain_scope]).to eq(canonical_domain)
      end
    end

    context 'with invalid domain' do
      let(:params) { { 'domain' => 'invalid.example.com' } }

      it 'returns nil without updating' do
        # Skip raise_concerns which would throw
        result = logic.process
        expect(result).to be_nil
      end

      it 'does not set greenlighted' do
        logic.process
        expect(logic.greenlighted).to be false
      end
    end
  end

  describe '#success_data' do
    it 'returns domain_scope' do
      data = logic.success_data
      expect(data[:domain_scope]).to eq(custom_domain)
    end

    it 'returns previous_domain_scope' do
      session['domain_scope'] = 'old.example.com'
      new_logic = described_class.new(strategy_result, params)
      data = new_logic.success_data
      expect(data[:previous_domain_scope]).to eq('old.example.com')
    end
  end

  describe 'domain validation' do
    context 'when domains feature is disabled' do
      before do
        allow(OT).to receive(:conf).and_return({
          'site' => {},
          'features' => { 'domains' => { 'enabled' => false } },
        })
      end

      it 'still allows canonical domain' do
        params['domain'] = canonical_domain
        logic = described_class.new(strategy_result, params)
        expect { logic.raise_concerns }.not_to raise_error
      end

      it 'rejects custom domains' do
        params['domain'] = custom_domain
        logic = described_class.new(strategy_result, params)
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Invalid domain/)
      end
    end
  end
end

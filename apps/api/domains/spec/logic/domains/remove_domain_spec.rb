# apps/api/domains/spec/logic/domains/remove_domain_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::Domains::RemoveDomain do
  let(:customer) do
    instance_double(
      Onetime::Customer,
      custid: 'cust123',
      objid: 'cust123',
      extid: 'ext-cust123',
      anonymous?: false,
    )
  end

  let(:custom_domain) do
    instance_double(
      Onetime::CustomDomain,
      identifier: 'domain123',
      display_domain: 'example.com',
      domainid: 'domain123',
      destroy!: true,
    )
  end

  let(:session) do
    {
      'csrf' => 'test-csrf-token',
      'domain_context' => 'example.com',
    }
  end

  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: customer,
      authenticated?: true,
      metadata: {},
    )
  end

  let(:params) { { 'extid' => 'ext-domain123' } }
  let(:logic) { described_class.new(strategy_result, params) }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)
    allow(OT).to receive(:conf).and_return({
      'site' => {},
      'features' => { 'domains' => { 'enabled' => true } },
    })

    allow(logic).to receive(:require_organization!)

    allow(Onetime::CustomDomain).to receive(:find_by_extid)
      .and_return(custom_domain)
    allow(custom_domain).to receive(:owner?).with(customer).and_return(true)
  end

  describe '#process' do
    let(:strategy) { instance_double(Onetime::DomainValidation::PassthroughStrategy) }
    let(:delete_result) { { status: 'deleted', message: 'Vhost deleted' } }

    before do
      allow(Onetime::DomainValidation::Strategy).to receive(:for_config)
        .and_return(strategy)
      allow(strategy).to receive(:delete_vhost).and_return(delete_result)

      logic.instance_variable_set(:@custom_domain, custom_domain)
      logic.instance_variable_set(:@display_domain, 'example.com')
    end

    it 'sets greenlighted flag' do
      logic.send(:process)
      expect(logic.greenlighted).to be true
    end

    it 'destroys the custom domain' do
      expect(custom_domain).to receive(:destroy!)
      logic.send(:process)
    end

    it 'deletes the vhost' do
      expect(strategy).to receive(:delete_vhost).with(custom_domain)
      logic.send(:process)
    end

    context 'domain_context clearing' do
      it 'clears domain_context when it matches the removed domain' do
        expect(session['domain_context']).to eq('example.com')
        logic.send(:process)
        expect(session['domain_context']).to be_nil
      end

      it 'leaves domain_context unchanged when it does not match' do
        session['domain_context'] = 'other-domain.com'
        logic.send(:process)
        expect(session['domain_context']).to eq('other-domain.com')
      end

      it 'handles nil domain_context gracefully' do
        session['domain_context'] = nil
        expect { logic.send(:process) }.not_to raise_error
        expect(session['domain_context']).to be_nil
      end
    end

    it 'continues processing despite vhost deletion errors' do
      allow(strategy).to receive(:delete_vhost)
        .and_raise(HTTParty::ResponseError, 'API error')

      expect(OT).to receive(:le).with(/delete_vhost error/)
      expect { logic.send(:process) }.not_to raise_error
    end
  end

  describe '#success_data' do
    before do
      logic.instance_variable_set(:@custom_domain, custom_domain)
      logic.instance_variable_set(:@display_domain, 'example.com')
    end

    it 'includes user_id' do
      data = logic.send(:success_data)
      expect(data[:user_id]).to eq(customer.objid)
    end

    it 'includes removal message' do
      data = logic.send(:success_data)
      expect(data[:message]).to eq('Removed example.com')
    end

    it 'returns empty record hash' do
      data = logic.send(:success_data)
      expect(data[:record]).to eq({})
    end
  end
end

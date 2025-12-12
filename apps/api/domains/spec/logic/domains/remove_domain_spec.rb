# apps/api/domains/spec/logic/domains/remove_domain_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::Domains::RemoveDomain do
  # Skip these tests - they require full integration environment
  # Tests need proper Onetime boot sequence, Redis, and model initialization
  # TODO: Set up integration test environment or convert to unit tests with better mocking

  before(:all) do
    skip 'Requires integration environment setup'
  end

  let(:customer) do
    double('Customer',
      custid: 'cust123',
      objid: 'cust123',
    )
  end

  let(:organization) do
    double('Organization',
      objid: 'org123',
      display_name: 'Test Org',
    )
  end

  let(:custom_domain) do
    double('CustomDomain',
      identifier: 'domain123',
      extid: 'dom_abc123',
      display_domain: 'example.com',
      domainid: 'domain123',
      org_id: 'org123',
      organization: organization,
      'owner?' => true,
      'destroy!' => true,
    )
  end

  let(:params) { { 'extid' => 'dom_abc123' } }
  let(:logic) { described_class.new(customer, params) }

  before do
    allow(logic).to receive(:organization).and_return(organization)
    allow(logic).to receive(:require_organization!)
    allow(Onetime::CustomDomain).to receive(:find_by_extid).and_return(custom_domain)
  end

  describe '#process' do
    before do
      allow(logic).to receive(:success_data).and_return({})
    end

    it 'destroys the custom domain' do
      expect(custom_domain).to receive(:destroy!).with(customer)
      logic.send(:process)
    end

    it 'sets greenlighted flag' do
      logic.send(:process)
      expect(logic.greenlighted).to be true
    end

    it 'sets display_domain' do
      logic.send(:process)
      expect(logic.display_domain).to eq('example.com')
    end
  end

  describe '#success_data' do
    before do
      logic.instance_variable_set(:@display_domain, 'example.com')
    end

    it 'includes user_id' do
      data = logic.send(:success_data)
      expect(data[:user_id]).to eq(customer.objid)
    end

    it 'includes empty record' do
      data = logic.send(:success_data)
      expect(data[:record]).to eq({})
    end

    it 'includes removal message' do
      data = logic.send(:success_data)
      expect(data[:message]).to include('example.com')
    end
  end

  describe 'telemetry events (domain.removed)' do
    before do
      allow(logic).to receive(:success_data).and_return({})
      logic.instance_variable_set(:@custom_domain, custom_domain)
    end

    it 'emits domain.removed telemetry event after destroying domain' do
      expect(Onetime::Jobs::Publisher).to receive(:enqueue_transient)
        .with('domain.removed', hash_including(domain: 'example.com'))

      logic.send(:process)
    end

    it 'includes organization_id in telemetry event' do
      expect(Onetime::Jobs::Publisher).to receive(:enqueue_transient)
        .with('domain.removed', hash_including(organization_id: 'org123'))

      logic.send(:process)
    end

    it 'does not fail if telemetry emission fails' do
      allow(Onetime::Jobs::Publisher).to receive(:enqueue_transient)
        .and_raise(StandardError, 'RabbitMQ down')

      expect { logic.send(:process) }.not_to raise_error
    end

    it 'does not emit telemetry if destroy fails' do
      allow(custom_domain).to receive(:destroy!).and_raise(StandardError, 'Destroy failed')

      expect(Onetime::Jobs::Publisher).not_to receive(:enqueue_transient)
      expect { logic.send(:process) }.to raise_error(StandardError)
    end
  end
end

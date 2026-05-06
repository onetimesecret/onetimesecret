# apps/api/domains/spec/logic/domains/verify_domain_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::Domains::VerifyDomain do
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
      display_domain: 'example.com',
      domainid: 'domain123',
      vhost: nil,
      'vhost=' => nil,
      resolving: nil,
      'resolving=' => nil,
      updated: nil,
      'updated=' => nil,
      save: true,
      verified!: true,
      safe_dump: { display_domain: 'example.com' },
    )
  end

  let(:params) { { 'domainid' => 'domain123' } }
  let(:logic) { described_class.new(customer, params) }

  before do
    allow(logic).to receive(:organization).and_return(organization)
    allow(logic).to receive(:require_organization!)
    allow(Onetime::CustomDomain).to receive(:load).and_return(custom_domain)
    allow(OT).to receive(:now).and_return(double(to_i: 1_234_567_890))
  end

  describe '#process' do
    let(:operation_result) do
      instance_double(
        Onetime::Operations::VerifyDomain::Result,
        dns_validated: true,
        is_resolving: true,
      )
    end

    before do
      allow(Onetime::Operations::VerifyDomain).to receive(:new)
        .with(domain: custom_domain, persist: true)
        .and_return(double(call: operation_result))
      allow(logic).to receive(:success_data).and_return({})
    end

    it 'delegates to Onetime::Operations::VerifyDomain' do
      expect(Onetime::Operations::VerifyDomain).to receive(:new)
        .with(domain: custom_domain, persist: true)
      logic.send(:process)
    end

    it 'returns success data' do
      expect(logic).to receive(:success_data)
      logic.send(:process)
    end
  end

  describe '#raise_concerns' do
    it 'does not require API key configuration' do
      # Previously required Approximated API key, now supports multiple strategies
      expect { logic.send(:raise_concerns) }.not_to raise_error
    end

    it 'calls parent raise_concerns' do
      # Verify it still calls super to inherit GetDomain concerns
      expect(logic).to receive(:require_organization!)
      logic.send(:raise_concerns)
    end
  end
end

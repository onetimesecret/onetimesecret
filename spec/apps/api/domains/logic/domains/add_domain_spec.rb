# spec/apps/api/domains/logic/domains/add_domain_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::Domains::AddDomain do
  # Skip these tests - they require full integration environment
  # Tests need proper Onetime boot sequence, Redis, and model initialization
  # TODO: Set up integration test environment or convert to unit tests with better mocking

  before(:all) do
    skip 'Requires integration environment setup'
  end

  let(:customer) do
    double('Customer',
           custid: 'cust123',
           objid: 'cust123')
  end

  let(:organization) do
    double('Organization',
           objid: 'org123',
           display_name: 'Test Org')
  end

  let(:custom_domain) do
    double('CustomDomain',
           identifier: 'domain123',
           display_domain: 'example.com',
           domainid: 'domain123',
           vhost: nil,
           'vhost=' => nil,
           updated: nil,
           'updated=' => nil,
           save: true,
           safe_dump: { display_domain: 'example.com' })
  end

  let(:params) { { 'domain' => 'example.com' } }
  let(:logic) { described_class.new(customer, params) }

  before do
    allow(logic).to receive(:organization).and_return(organization)
    allow(logic).to receive(:require_organization!)
    allow(Onetime::CustomDomain).to receive(:valid?).and_return(true)
    allow(Onetime::CustomDomain).to receive(:parse).and_return(custom_domain)
    allow(Onetime::CustomDomain).to receive(:load_by_display_domain).and_return(nil)
    allow(Onetime::CustomDomain).to receive(:create!).and_return(custom_domain)
    allow(Onetime::Cluster::Features).to receive(:cluster_safe_dump).and_return({})
    allow(OT.conf).to receive(:dig).and_return(nil)
  end

  describe '#request_certificate' do
    let(:strategy) { instance_double(Onetime::DomainValidation::ApproximatedStrategy) }

    before do
      allow(Onetime::DomainValidation::Strategy).to receive(:for_config)
        .and_return(strategy)
    end

    context 'with successful certificate request' do
      let(:result) do
        {
          status: 'requested',
          message: 'Certificate requested',
          data: { 'vhost_id' => '123', 'status' => 'PENDING' }
        }
      end

      before do
        allow(strategy).to receive(:request_certificate).and_return(result)
      end

      it 'calls strategy request_certificate' do
        expect(strategy).to receive(:request_certificate).with(custom_domain)
        logic.send(:request_certificate)
      end

      it 'stores vhost data when present' do
        expect(custom_domain).to receive(:vhost=)
          .with(result[:data].to_json)
        logic.send(:request_certificate)
      end

      it 'updates timestamp' do
        expect(custom_domain).to receive(:updated=)
        logic.send(:request_certificate)
      end

      it 'saves custom domain' do
        expect(custom_domain).to receive(:save)
        logic.send(:request_certificate)
      end

      it 'returns result hash' do
        result_returned = logic.send(:request_certificate)
        expect(result_returned).to eq(result)
      end

      it 'logs certificate request' do
        expect(OT).to receive(:info).with(/request_certificate.*requested/)
        logic.send(:request_certificate)
      end
    end

    context 'without data in result' do
      let(:result) { { status: 'external', message: 'Handled externally' } }

      before do
        allow(strategy).to receive(:request_certificate).and_return(result)
      end

      it 'does not store vhost data' do
        expect(custom_domain).not_to receive(:vhost=)
        logic.send(:request_certificate)
      end

      it 'does not save custom domain' do
        expect(custom_domain).not_to receive(:save)
        logic.send(:request_certificate)
      end
    end

    context 'with different strategies' do
      context 'approximated strategy' do
        let(:strategy) { instance_double(Onetime::DomainValidation::ApproximatedStrategy) }
        let(:result) { { status: 'requested', data: { 'vhost' => 'data' } } }

        before do
          allow(Onetime::DomainValidation::Strategy).to receive(:for_config)
            .and_return(strategy)
          allow(strategy).to receive(:request_certificate).and_return(result)
        end

        it 'uses approximated strategy' do
          expect(strategy).to receive(:request_certificate)
          logic.send(:request_certificate)
        end
      end

      context 'passthrough strategy' do
        let(:strategy) { instance_double(Onetime::DomainValidation::PassthroughStrategy) }
        let(:result) { { status: 'external', mode: 'passthrough' } }

        before do
          allow(Onetime::DomainValidation::Strategy).to receive(:for_config)
            .and_return(strategy)
          allow(strategy).to receive(:request_certificate).and_return(result)
        end

        it 'uses passthrough strategy' do
          expect(strategy).to receive(:request_certificate)
          logic.send(:request_certificate)
        end
      end

      context 'caddy on-demand strategy' do
        let(:strategy) { instance_double(Onetime::DomainValidation::CaddyOnDemandStrategy) }
        let(:result) { { status: 'delegated', mode: 'caddy_on_demand' } }

        before do
          allow(Onetime::DomainValidation::Strategy).to receive(:for_config)
            .and_return(strategy)
          allow(strategy).to receive(:request_certificate).and_return(result)
        end

        it 'uses caddy on-demand strategy' do
          expect(strategy).to receive(:request_certificate)
          logic.send(:request_certificate)
        end
      end
    end
  end

  describe '#process' do
    let(:strategy) { instance_double(Onetime::DomainValidation::PassthroughStrategy) }
    let(:result) { { status: 'external' } }

    before do
      allow(Onetime::DomainValidation::Strategy).to receive(:for_config)
        .and_return(strategy)
      allow(strategy).to receive(:request_certificate).and_return(result)
      allow(logic).to receive(:success_data).and_return({})
    end

    it 'creates custom domain' do
      expect(Onetime::CustomDomain).to receive(:create!)
        .with('example.com', organization.objid)
      logic.send(:process)
    end

    it 'requests certificate' do
      expect(logic).to receive(:request_certificate)
      logic.send(:process)
    end

    it 'continues processing despite HTTParty errors' do
      allow(strategy).to receive(:request_certificate)
        .and_raise(HTTParty::ResponseError, 'API error')

      expect(OT).to receive(:le).with(/request_certificate error/)
      expect { logic.send(:process) }.not_to raise_error
    end

    it 'continues processing despite standard errors' do
      allow(strategy).to receive(:request_certificate)
        .and_raise(StandardError, 'Unexpected error')

      expect(OT).to receive(:le).with(/Unexpected error/)
      expect { logic.send(:process) }.not_to raise_error
    end

    it 'sets greenlighted flag' do
      logic.send(:process)
      expect(logic.greenlighted).to be true
    end
  end

  describe '#create_vhost (deprecated)' do
    let(:strategy) { instance_double(Onetime::DomainValidation::PassthroughStrategy) }
    let(:result) { { status: 'external' } }

    before do
      allow(Onetime::DomainValidation::Strategy).to receive(:for_config)
        .and_return(strategy)
      allow(strategy).to receive(:request_certificate).and_return(result)
    end

    it 'delegates to request_certificate' do
      expect(logic).to receive(:request_certificate)
      logic.send(:create_vhost)
    end
  end

  describe '#success_data' do
    before do
      logic.instance_variable_set(:@custom_domain, custom_domain)
    end

    it 'includes user_id' do
      data = logic.send(:success_data)
      expect(data[:user_id]).to eq(customer.objid)
    end

    it 'includes custom domain safe_dump' do
      expect(custom_domain).to receive(:safe_dump)
      logic.send(:success_data)
    end

    it 'includes cluster details' do
      data = logic.send(:success_data)
      expect(data[:details]).to have_key(:cluster)
    end
  end
end

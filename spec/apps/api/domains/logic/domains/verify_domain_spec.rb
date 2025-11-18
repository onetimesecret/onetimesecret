# spec/apps/api/domains/logic/domains/verify_domain_spec.rb
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
           resolving: nil,
           'resolving=' => nil,
           updated: nil,
           'updated=' => nil,
           save: true,
           verified!: true,
           safe_dump: { display_domain: 'example.com' })
  end

  let(:params) { { 'domainid' => 'domain123' } }
  let(:logic) { described_class.new(customer, params) }

  before do
    allow(logic).to receive(:organization).and_return(organization)
    allow(logic).to receive(:require_organization!)
    allow(Onetime::CustomDomain).to receive(:load).and_return(custom_domain)
    allow(OT).to receive(:now).and_return(double(to_i: 1234567890))
  end

  describe '#refresh_status' do
    let(:strategy) { instance_double(Onetime::DomainValidation::ApproximatedStrategy) }

    context 'with successful status check' do
      let(:status_result) do
        {
          ready: true,
          has_ssl: true,
          is_resolving: true,
          status: 'ACTIVE_SSL',
          data: { 'vhost_id' => '123', 'status' => 'ACTIVE_SSL' }
        }
      end

      before do
        allow(strategy).to receive(:check_status).and_return(status_result)
      end

      it 'calls strategy check_status' do
        expect(strategy).to receive(:check_status).with(custom_domain)
        logic.send(:refresh_status, strategy)
      end

      it 'stores vhost data when present' do
        expect(custom_domain).to receive(:vhost=)
          .with(status_result[:data].to_json)
        logic.send(:refresh_status, strategy)
      end

      it 'updates resolving status when present' do
        expect(custom_domain).to receive(:resolving=).with('true')
        logic.send(:refresh_status, strategy)
      end

      it 'updates timestamp' do
        expect(custom_domain).to receive(:updated=).with(1234567890)
        logic.send(:refresh_status, strategy)
      end

      it 'saves custom domain' do
        expect(custom_domain).to receive(:save)
        logic.send(:refresh_status, strategy)
      end

      it 'logs status check' do
        expect(OT).to receive(:info).with(/refresh_status.*true/)
        logic.send(:refresh_status, strategy)
      end
    end

    context 'with false resolving status' do
      let(:status_result) do
        {
          ready: false,
          has_ssl: false,
          is_resolving: false,
          data: { 'status' => 'PENDING' }
        }
      end

      before do
        allow(strategy).to receive(:check_status).and_return(status_result)
      end

      it 'sets resolving to false string' do
        expect(custom_domain).to receive(:resolving=).with('false')
        logic.send(:refresh_status, strategy)
      end

      it 'still saves the domain' do
        expect(custom_domain).to receive(:save)
        logic.send(:refresh_status, strategy)
      end
    end

    context 'with nil resolving status' do
      let(:status_result) do
        {
          ready: true,
          has_ssl: true,
          is_resolving: nil,
          data: { 'status' => 'ACTIVE_SSL' }
        }
      end

      before do
        allow(strategy).to receive(:check_status).and_return(status_result)
      end

      it 'does not update resolving status' do
        expect(custom_domain).not_to receive(:resolving=)
        logic.send(:refresh_status, strategy)
      end
    end

    context 'without data in result' do
      let(:status_result) do
        {
          ready: true,
          message: 'External management',
          mode: 'passthrough'
        }
      end

      before do
        allow(strategy).to receive(:check_status).and_return(status_result)
      end

      it 'does not store vhost data' do
        expect(custom_domain).not_to receive(:vhost=)
        logic.send(:refresh_status, strategy)
      end

      it 'does not save custom domain' do
        expect(custom_domain).not_to receive(:save)
        logic.send(:refresh_status, strategy)
      end
    end

    context 'with error during status check' do
      before do
        allow(strategy).to receive(:check_status)
          .and_raise(StandardError, 'API timeout')
      end

      it 'logs error and continues' do
        expect(OT).to receive(:le).with(/refresh_status.*Error/)
        expect { logic.send(:refresh_status, strategy) }.not_to raise_error
      end

      it 'does not save custom domain' do
        expect(custom_domain).not_to receive(:save)
        logic.send(:refresh_status, strategy)
      end
    end
  end

  describe '#refresh_validation' do
    let(:strategy) { instance_double(Onetime::DomainValidation::ApproximatedStrategy) }

    context 'with successful validation' do
      let(:validation_result) do
        {
          validated: true,
          message: 'TXT record validated',
          data: [{ 'match' => true }]
        }
      end

      before do
        allow(strategy).to receive(:validate_ownership).and_return(validation_result)
      end

      it 'calls strategy validate_ownership' do
        expect(strategy).to receive(:validate_ownership).with(custom_domain)
        logic.send(:refresh_validation, strategy)
      end

      it 'marks domain as verified' do
        expect(custom_domain).to receive(:verified!).with(true)
        logic.send(:refresh_validation, strategy)
      end

      it 'logs validation result' do
        expect(OT).to receive(:info).with(/refresh_validation.*true/)
        logic.send(:refresh_validation, strategy)
      end
    end

    context 'with failed validation' do
      let(:validation_result) do
        {
          validated: false,
          message: 'TXT record not found'
        }
      end

      before do
        allow(strategy).to receive(:validate_ownership).and_return(validation_result)
      end

      it 'marks domain as not verified' do
        expect(custom_domain).to receive(:verified!).with(false)
        logic.send(:refresh_validation, strategy)
      end

      it 'logs validation result' do
        expect(OT).to receive(:info).with(/refresh_validation.*false/)
        logic.send(:refresh_validation, strategy)
      end
    end

    context 'with error during validation' do
      before do
        allow(strategy).to receive(:validate_ownership)
          .and_raise(StandardError, 'DNS lookup failed')
      end

      it 'logs error and continues' do
        expect(OT).to receive(:le).with(/refresh_validation.*Error/)
        expect { logic.send(:refresh_validation, strategy) }.not_to raise_error
      end

      it 'does not update verification status' do
        expect(custom_domain).not_to receive(:verified!)
        logic.send(:refresh_validation, strategy)
      end
    end
  end

  describe '#process' do
    let(:strategy) { instance_double(Onetime::DomainValidation::PassthroughStrategy) }
    let(:status_result) { { ready: true, mode: 'passthrough' } }
    let(:validation_result) { { validated: true, mode: 'passthrough' } }

    before do
      allow(Onetime::DomainValidation::Strategy).to receive(:for_config)
        .and_return(strategy)
      allow(strategy).to receive(:check_status).and_return(status_result)
      allow(strategy).to receive(:validate_ownership).and_return(validation_result)
      allow(logic).to receive(:success_data).and_return({})
    end

    it 'creates strategy from config' do
      expect(Onetime::DomainValidation::Strategy).to receive(:for_config)
        .with(OT.conf)
      logic.send(:process)
    end

    it 'refreshes status' do
      expect(logic).to receive(:refresh_status).with(strategy)
      logic.send(:process)
    end

    it 'refreshes validation' do
      expect(logic).to receive(:refresh_validation).with(strategy)
      logic.send(:process)
    end

    it 'returns success data' do
      expect(logic).to receive(:success_data)
      logic.send(:process)
    end

    it 'continues processing despite status errors' do
      allow(logic).to receive(:refresh_status)
        .and_raise(StandardError, 'Status error')

      expect(OT).to receive(:le).with(/refresh_status.*Error/)
      expect { logic.send(:process) }.not_to raise_error
    end

    it 'continues processing despite validation errors' do
      allow(logic).to receive(:refresh_validation)
        .and_raise(StandardError, 'Validation error')

      expect(OT).to receive(:le).with(/refresh_validation.*Error/)
      expect { logic.send(:process) }.not_to raise_error
    end
  end

  describe '#refresh_vhost (deprecated)' do
    let(:strategy) { instance_double(Onetime::DomainValidation::ApproximatedStrategy) }
    let(:status_result) { { ready: true, data: {} } }

    before do
      allow(Onetime::DomainValidation::Strategy).to receive(:for_config)
        .and_return(strategy)
      allow(strategy).to receive(:check_status).and_return(status_result)
    end

    it 'delegates to refresh_status' do
      expect(logic).to receive(:refresh_status).with(strategy)
      logic.send(:refresh_vhost)
    end

    it 'creates strategy from config' do
      expect(Onetime::DomainValidation::Strategy).to receive(:for_config)
        .with(OT.conf)
      logic.send(:refresh_vhost)
    end
  end

  describe '#refresh_txt_record_status (deprecated)' do
    let(:strategy) { instance_double(Onetime::DomainValidation::ApproximatedStrategy) }
    let(:validation_result) { { validated: true } }

    before do
      allow(Onetime::DomainValidation::Strategy).to receive(:for_config)
        .and_return(strategy)
      allow(strategy).to receive(:validate_ownership).and_return(validation_result)
    end

    it 'delegates to refresh_validation' do
      expect(logic).to receive(:refresh_validation).with(strategy)
      logic.send(:refresh_txt_record_status)
    end

    it 'creates strategy from config' do
      expect(Onetime::DomainValidation::Strategy).to receive(:for_config)
        .with(OT.conf)
      logic.send(:refresh_txt_record_status)
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

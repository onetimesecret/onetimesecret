# spec/lib/onetime/domain_validation/strategy_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/domain_validation/strategy'

RSpec.describe Onetime::DomainValidation::Strategy do
  let(:config) { { 'features' => { 'domains' => { 'strategy' => strategy_name } } } }
  let(:custom_domain) do
    double('CustomDomain',
           display_domain: 'example.com',
           txt_validation_value: 'validation123',
           validation_record: '_onetime-challenge-abc123.example.com',
           ready?: true)
  end

  describe '.for_config' do
    context 'with approximated strategy' do
      let(:strategy_name) { 'approximated' }

      it 'returns ApproximatedStrategy instance' do
        strategy = described_class.for_config(config)
        expect(strategy).to be_a(Onetime::DomainValidation::ApproximatedStrategy)
      end
    end

    context 'with passthrough strategy' do
      let(:strategy_name) { 'passthrough' }

      it 'returns PassthroughStrategy instance' do
        strategy = described_class.for_config(config)
        expect(strategy).to be_a(Onetime::DomainValidation::PassthroughStrategy)
      end
    end

    context 'with external strategy (alias for passthrough)' do
      let(:strategy_name) { 'external' }

      it 'returns PassthroughStrategy instance' do
        strategy = described_class.for_config(config)
        expect(strategy).to be_a(Onetime::DomainValidation::PassthroughStrategy)
      end
    end

    context 'with caddy_on_demand strategy' do
      let(:strategy_name) { 'caddy_on_demand' }

      it 'returns CaddyOnDemandStrategy instance' do
        strategy = described_class.for_config(config)
        expect(strategy).to be_a(Onetime::DomainValidation::CaddyOnDemandStrategy)
      end
    end

    context 'with caddy strategy (alias for caddy_on_demand)' do
      let(:strategy_name) { 'caddy' }

      it 'returns CaddyOnDemandStrategy instance' do
        strategy = described_class.for_config(config)
        expect(strategy).to be_a(Onetime::DomainValidation::CaddyOnDemandStrategy)
      end
    end

    context 'with unknown strategy' do
      let(:strategy_name) { 'unknown_strategy' }

      context 'without strict mode' do
        it 'logs error and returns PassthroughStrategy' do
          expect(OT).to receive(:le).with(/Unknown strategy/)
          strategy = described_class.for_config(config)
          expect(strategy).to be_a(Onetime::DomainValidation::PassthroughStrategy)
        end
      end

      context 'with strict mode enabled' do
        let(:config) do
          {
            'features' => {
              'domains' => {
                'strategy' => strategy_name,
                'strict_strategy' => true
              }
            }
          }
        end

        it 'raises ArgumentError' do
          expect do
            described_class.for_config(config)
          end.to raise_error(ArgumentError, /Unknown domain validation strategy/)
        end

        it 'includes valid options in error message' do
          expect do
            described_class.for_config(config)
          end.to raise_error(ArgumentError, /approximated, passthrough, caddy_on_demand/)
        end
      end
    end

    context 'with no strategy configured (default)' do
      let(:config) { { 'features' => { 'domains' => {} } } }

      it 'defaults to passthrough strategy' do
        strategy = described_class.for_config(config)
        expect(strategy).to be_a(Onetime::DomainValidation::PassthroughStrategy)
      end
    end

    context 'with case variations' do
      let(:strategy_name) { 'PASSTHROUGH' }

      it 'handles case-insensitive strategy names' do
        strategy = described_class.for_config(config)
        expect(strategy).to be_a(Onetime::DomainValidation::PassthroughStrategy)
      end
    end
  end

  describe '.handle_unknown_strategy' do
    let(:strategy_name) { 'invalid' }
    let(:config) { {} }

    context 'with strict mode disabled' do
      let(:strict_mode) { false }

      it 'logs error message' do
        expect(OT).to receive(:le).with(/Unknown strategy: 'invalid'/)
        described_class.handle_unknown_strategy(strategy_name, strict_mode, config)
      end

      it 'returns PassthroughStrategy' do
        allow(OT).to receive(:le)
        result = described_class.handle_unknown_strategy(strategy_name, strict_mode, config)
        expect(result).to be_a(Onetime::DomainValidation::PassthroughStrategy)
      end
    end

    context 'with strict mode enabled' do
      let(:strict_mode) { true }

      it 'raises ArgumentError' do
        expect do
          described_class.handle_unknown_strategy(strategy_name, strict_mode, config)
        end.to raise_error(ArgumentError)
      end
    end
  end
end

RSpec.describe Onetime::DomainValidation::ApproximatedStrategy do
  let(:config) { {} }
  let(:strategy) { described_class.new(config) }
  let(:custom_domain) do
    double('CustomDomain',
           display_domain: 'example.com',
           txt_validation_value: 'validation123',
           validation_record: '_onetime-challenge-abc123.example.com')
  end

  before do
    allow(Onetime::Cluster::Features).to receive(:api_key).and_return('test_api_key')
    allow(Onetime::Cluster::Features).to receive(:vhost_target).and_return('app.example.com')
  end

  describe '#validate_ownership' do
    context 'when API key is not configured' do
      before do
        allow(Onetime::Cluster::Features).to receive(:api_key).and_return(nil)
      end

      it 'returns not validated with error message' do
        result = strategy.validate_ownership(custom_domain)
        expect(result[:validated]).to be false
        expect(result[:message]).to include('API key not configured')
      end
    end

    context 'when API call succeeds with match' do
      let(:api_response) do
        double('Response',
               code: 200,
               parsed_response: {
                 'records' => [
                   { 'match' => true, 'address' => custom_domain.validation_record }
                 ]
               })
      end

      before do
        allow(Onetime::Cluster::Approximated).to receive(:check_records_match_exactly)
          .and_return(api_response)
      end

      it 'returns validated true' do
        result = strategy.validate_ownership(custom_domain)
        expect(result[:validated]).to be true
      end

      it 'includes validation message' do
        result = strategy.validate_ownership(custom_domain)
        expect(result[:message]).to eq('TXT record validated')
      end

      it 'includes record data' do
        result = strategy.validate_ownership(custom_domain)
        expect(result[:data]).to be_an(Array)
      end
    end

    context 'when API call succeeds with no match' do
      let(:api_response) do
        double('Response',
               code: 200,
               parsed_response: {
                 'records' => [
                   { 'match' => false, 'address' => custom_domain.validation_record }
                 ]
               })
      end

      before do
        allow(Onetime::Cluster::Approximated).to receive(:check_records_match_exactly)
          .and_return(api_response)
      end

      it 'returns validated false' do
        result = strategy.validate_ownership(custom_domain)
        expect(result[:validated]).to be false
      end

      it 'includes descriptive message' do
        result = strategy.validate_ownership(custom_domain)
        expect(result[:message]).to include('not found or mismatch')
      end
    end

    context 'when API call fails' do
      let(:api_response) do
        double('Response',
               code: 500,
               parsed_response: { 'error' => 'Server error' })
      end

      before do
        allow(Onetime::Cluster::Approximated).to receive(:check_records_match_exactly)
          .and_return(api_response)
      end

      it 'returns validated false' do
        result = strategy.validate_ownership(custom_domain)
        expect(result[:validated]).to be false
      end

      it 'includes error code in message' do
        result = strategy.validate_ownership(custom_domain)
        expect(result[:message]).to include('500')
      end
    end

    context 'when exception occurs' do
      before do
        allow(Onetime::Cluster::Approximated).to receive(:check_records_match_exactly)
          .and_raise(StandardError, 'Network error')
      end

      it 'logs error' do
        expect(OT).to receive(:le).with(/Error validating/)
        strategy.validate_ownership(custom_domain)
      end

      it 'returns validated false' do
        allow(OT).to receive(:le)
        result = strategy.validate_ownership(custom_domain)
        expect(result[:validated]).to be false
      end
    end
  end

  describe '#request_certificate' do
    context 'when API key is not configured' do
      before do
        allow(Onetime::Cluster::Features).to receive(:api_key).and_return(nil)
      end

      it 'returns error status' do
        result = strategy.request_certificate(custom_domain)
        expect(result[:status]).to eq('error')
      end
    end

    context 'when vhost creation succeeds' do
      let(:api_response) do
        double('Response',
               code: 200,
               parsed_response: {
                 'data' => {
                   'status' => 'PENDING',
                   'incoming_address' => 'example.com'
                 }
               })
      end

      before do
        allow(Onetime::Cluster::Approximated).to receive(:create_vhost)
          .and_return(api_response)
      end

      it 'returns requested status' do
        result = strategy.request_certificate(custom_domain)
        expect(result[:status]).to eq('requested')
      end

      it 'includes response data' do
        result = strategy.request_certificate(custom_domain)
        expect(result[:data]).to be_a(Hash)
        expect(result[:data]['status']).to eq('PENDING')
      end
    end

    context 'when vhost creation fails' do
      let(:api_response) do
        double('Response',
               code: 422,
               parsed_response: { 'error' => 'Invalid domain' })
      end

      before do
        allow(Onetime::Cluster::Approximated).to receive(:create_vhost)
          .and_return(api_response)
      end

      it 'returns error status' do
        result = strategy.request_certificate(custom_domain)
        expect(result[:status]).to eq('error')
      end
    end
  end

  describe '#check_status' do
    context 'when API key is not configured' do
      before do
        allow(Onetime::Cluster::Features).to receive(:api_key).and_return(nil)
      end

      it 'returns not ready' do
        result = strategy.check_status(custom_domain)
        expect(result[:ready]).to be false
      end
    end

    context 'when domain has active SSL' do
      let(:api_response) do
        double('Response',
               code: 200,
               parsed_response: {
                 'data' => {
                   'status' => 'ACTIVE_SSL',
                   'has_ssl' => true,
                   'is_resolving' => true,
                   'status_message' => 'Active with SSL'
                 }
               })
      end

      before do
        allow(Onetime::Cluster::Approximated).to receive(:get_vhost_by_incoming_address)
          .and_return(api_response)
      end

      it 'returns ready true' do
        result = strategy.check_status(custom_domain)
        expect(result[:ready]).to be true
      end

      it 'includes SSL status' do
        result = strategy.check_status(custom_domain)
        expect(result[:has_ssl]).to be true
      end

      it 'includes resolving status' do
        result = strategy.check_status(custom_domain)
        expect(result[:is_resolving]).to be true
      end
    end

    context 'when domain is not active' do
      let(:api_response) do
        double('Response',
               code: 200,
               parsed_response: {
                 'data' => {
                   'status' => 'PENDING',
                   'has_ssl' => false,
                   'is_resolving' => true
                 }
               })
      end

      before do
        allow(Onetime::Cluster::Approximated).to receive(:get_vhost_by_incoming_address)
          .and_return(api_response)
      end

      it 'returns ready false' do
        result = strategy.check_status(custom_domain)
        expect(result[:ready]).to be false
      end
    end
  end
end

RSpec.describe Onetime::DomainValidation::PassthroughStrategy do
  let(:config) { {} }
  let(:strategy) { described_class.new(config) }
  let(:custom_domain) { double('CustomDomain', display_domain: 'example.com') }

  describe '#validate_ownership' do
    it 'always returns validated true' do
      result = strategy.validate_ownership(custom_domain)
      expect(result[:validated]).to be true
    end

    it 'indicates passthrough mode' do
      result = strategy.validate_ownership(custom_domain)
      expect(result[:mode]).to eq('passthrough')
    end

    it 'includes explanatory message' do
      result = strategy.validate_ownership(custom_domain)
      expect(result[:message]).to include('External validation')
    end
  end

  describe '#request_certificate' do
    it 'returns external status' do
      result = strategy.request_certificate(custom_domain)
      expect(result[:status]).to eq('external')
    end

    it 'indicates passthrough mode' do
      result = strategy.request_certificate(custom_domain)
      expect(result[:mode]).to eq('passthrough')
    end
  end

  describe '#check_status' do
    it 'always returns ready true' do
      result = strategy.check_status(custom_domain)
      expect(result[:ready]).to be true
    end

    it 'assumes SSL is available' do
      result = strategy.check_status(custom_domain)
      expect(result[:has_ssl]).to be true
    end

    it 'assumes domain is resolving' do
      result = strategy.check_status(custom_domain)
      expect(result[:is_resolving]).to be true
    end
  end
end

RSpec.describe Onetime::DomainValidation::CaddyOnDemandStrategy do
  let(:config) { {} }
  let(:strategy) { described_class.new(config) }
  let(:custom_domain) { double('CustomDomain', display_domain: 'example.com') }

  describe '#validate_ownership' do
    it 'returns validated true' do
      result = strategy.validate_ownership(custom_domain)
      expect(result[:validated]).to be true
    end

    it 'indicates caddy_on_demand mode' do
      result = strategy.validate_ownership(custom_domain)
      expect(result[:mode]).to eq('caddy_on_demand')
    end

    it 'explains validation is delegated to Caddy' do
      result = strategy.validate_ownership(custom_domain)
      expect(result[:message]).to include('Caddy')
    end
  end

  describe '#request_certificate' do
    it 'returns delegated status' do
      result = strategy.request_certificate(custom_domain)
      expect(result[:status]).to eq('delegated')
    end

    it 'indicates caddy_on_demand mode' do
      result = strategy.request_certificate(custom_domain)
      expect(result[:mode]).to eq('caddy_on_demand')
    end
  end

  describe '#check_status' do
    it 'returns ready true' do
      result = strategy.check_status(custom_domain)
      expect(result[:ready]).to be true
    end

    it 'returns nil for has_ssl (unknown)' do
      result = strategy.check_status(custom_domain)
      expect(result[:has_ssl]).to be_nil
    end

    it 'returns nil for is_resolving (unknown)' do
      result = strategy.check_status(custom_domain)
      expect(result[:is_resolving]).to be_nil
    end
  end
end

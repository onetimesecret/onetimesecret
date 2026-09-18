# spec/unit/onetime/domain_validation/strategy_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/domain_validation/strategy'

RSpec.describe Onetime::DomainValidation::Strategy do
  let(:config) { { 'features' => { 'domains' => { 'validation_strategy' => strategy_name } } } }
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
                'validation_strategy' => strategy_name,
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
  let(:answer_class) { Onetime::DomainValidation::TxtResolver::Answer }
  # The native fallback runs the real TxtVerifier over a fake resolver, so no
  # example opens a socket. NXDOMAIN unless a context says otherwise.
  let(:native_rcode) { Resolv::DNS::RCode::NXDomain }
  let(:native_values) { [] }
  let(:resolver) { instance_double(Onetime::DomainValidation::TxtResolver, close: nil) }
  let(:txt_verifier) { Onetime::DomainValidation::TxtVerifier.new(resolver_factory: -> { resolver }) }
  let(:strategy) { described_class.new(config, txt_verifier: txt_verifier) }
  let(:verified) { false }
  let(:custom_domain) do
    double('CustomDomain',
           display_domain: 'example.com',
           txt_validation_value: 'validation123',
           validation_record: '_onetime-challenge-abc123.example.com',
           verified: verified)
  end

  before do
    allow(Onetime::DomainValidation::Features).to receive(:api_key).and_return('test_api_key')
    allow(Onetime::DomainValidation::Features).to receive(:vhost_target).and_return('app.example.com')
    allow(resolver).to receive(:lookup)
      .with(custom_domain.validation_record) { answer_class.new(rcode: native_rcode, values: native_values) }
  end

  it 'defaults to a TxtVerifier for the native fallback' do
    expect(described_class.new(config).txt_verifier).to be_a(Onetime::DomainValidation::TxtVerifier)
  end

  describe '#bulk_rate_limit' do
    it 'paces bulk runs for the API rate cap' do
      expect(strategy.bulk_rate_limit).to eq(0.5)
    end
  end

  describe '#proves_ownership?' do
    it 'is true: a pass means the TXT record was checked' do
      expect(strategy.proves_ownership?).to be(true)
    end
  end

  describe '#validate_ownership' do
    context 'when API key is not configured' do
      before do
        allow(Onetime::DomainValidation::Features).to receive(:api_key).and_return(nil)
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
        allow(Onetime::DomainValidation::ApproximatedClient).to receive(:check_records_match_exactly)
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
                   { 'match' => false, 'actual_values' => actual_values, 'address' => custom_domain.validation_record }
                 ]
               })
      end
      let(:actual_values) { [] }

      before do
        allow(Onetime::DomainValidation::ApproximatedClient).to receive(:check_records_match_exactly)
          .and_return(api_response)
      end

      it 'returns validated false' do
        result = strategy.validate_ownership(custom_domain)
        expect(result[:validated]).to be false
      end

      it 'reports not found when the checker saw no values' do
        result = strategy.validate_ownership(custom_domain)
        expect(result[:message]).to eq('TXT record not found')
      end

      context 'with values that do not match exactly' do
        let(:actual_values) { %w[validation123 something-else] }

        it 'reports a mismatch with the value count' do
          result = strategy.validate_ownership(custom_domain)
          expect(result[:validated]).to be false
          expect(result[:message]).to include('mismatch (2 value(s) found')
        end
      end

      it 'never falls back to a native lookup' do
        expect(resolver).not_to receive(:lookup)
        strategy.validate_ownership(custom_domain)
      end

      context 'when the domain is already verified' do
        let(:verified) { true }

        it 'still fails definitively on the upstream answer' do
          result = strategy.validate_ownership(custom_domain)
          expect(result).to include(validated: false)
          expect(result).not_to have_key(:indeterminate)
        end
      end
    end

    # Approximated's contract: actual_values is `false` "when DNS resolution or
    # the record-type lookup failed". Observed for a correctly-configured
    # tenant on 2026-09-18; treating it as a mismatch demoted the domain on
    # every refresh run.
    context 'when the checker answers 200 but its own lookup failed (actual_values: false)' do
      let(:primary_response) do
        double('Response',
               code: 200,
               parsed_response: {
                 'records' => [
                   { 'actual_values' => false, 'address' => custom_domain.validation_record,
                     'match' => false, 'match_against' => 'validation123', 'type' => 'TXT' }
                 ]
               })
      end
      # Upstream gave no answer, so the native lookup decides. SERVFAIL keeps
      # it indeterminate for the examples below unless a context overrides.
      let(:native_rcode) { Resolv::DNS::RCode::ServFail }

      before do
        allow(Onetime::DomainValidation::ApproximatedClient).to receive(:check_records_match_exactly)
          .and_return(primary_response)
        allow(OT).to receive(:lw)
      end

      context 'and the native lookup is indeterminate too (SERVFAIL)' do
        it 'returns validated nil and flags the result indeterminate' do
          result = strategy.validate_ownership(custom_domain)
          expect(result[:validated]).to be_nil
          expect(result[:indeterminate]).to be true
          expect(result[:message]).to include('indeterminate')
        end

        it 'keeps the raw upstream payload first, appends the native record, and logs' do
          expect(OT).to receive(:lw).with(/Indeterminate TXT check.*"actual_values" *=> *false/)
          result = strategy.validate_ownership(custom_domain)
          expect(result[:data].first['actual_values']).to be false
          expect(result[:data].last).to include('actual_values' => false, 'error' => 'SERVFAIL')
          expect(result[:message]).to include('native lookup:').and include('SERVFAIL')
        end

        it 'makes one Approximated request per indeterminate domain' do
          domains = 3.times.map do |index|
            double('CustomDomain',
              display_domain: "example#{index}.com",
              txt_validation_value: custom_domain.txt_validation_value,
              validation_record: custom_domain.validation_record)
          end
          expect(Onetime::DomainValidation::ApproximatedClient)
            .to receive(:check_records_match_exactly).exactly(domains.size).times.and_return(primary_response)

          domains.each { |domain| strategy.validate_ownership(domain) }
        end
      end

      context 'and the native lookup times out' do
        before do
          allow(resolver).to receive(:lookup)
            .and_raise(Onetime::DomainValidation::TxtResolver::NoReplyError, 'no reply')
        end

        it 'stays indeterminate' do
          result = strategy.validate_ownership(custom_domain)
          expect(result[:validated]).to be_nil
          expect(result[:indeterminate]).to be true
        end
      end

      context 'and the native lookup is REFUSED' do
        let(:native_rcode) { Resolv::DNS::RCode::Refused }

        it 'stays indeterminate' do
          expect(strategy.validate_ownership(custom_domain)).to include(validated: nil, indeterminate: true)
        end
      end

      context 'and the native lookup returns exactly the challenge value' do
        let(:native_rcode) { Resolv::DNS::RCode::NoError }
        let(:native_values) { ['validation123'] }

        it 'validates from the native answer' do
          result = strategy.validate_ownership(custom_domain)
          expect(result[:validated]).to be true
          expect(result[:source]).to eq('native')
          expect(result[:message]).to eq('TXT record validated (native lookup; upstream checker indeterminate)')
        end

        it 'does not issue a NXDOMAIN probe when the native lookup promotes' do
          expect(Onetime::DomainValidation::ApproximatedClient)
            .to receive(:check_records_match_exactly).once.and_return(primary_response)
          strategy.validate_ownership(custom_domain)
        end
      end

      context 'and the native lookup answers NXDOMAIN' do
        let(:native_rcode) { Resolv::DNS::RCode::NXDomain }

        context 'when the domain has never been confirmed' do
          it 'fails closed from the native answer' do
            result = strategy.validate_ownership(custom_domain)
            expect(result).to include(validated: false, source: 'native')
            expect(result).not_to have_key(:indeterminate)
            expect(result[:message]).to eq('TXT record not found (native lookup; upstream checker indeterminate)')
          end

          it 'carries :data so VerifyDomain persists the failed check' do
            result = strategy.validate_ownership(custom_domain)
            expect(result[:data].first['actual_values']).to be false
            expect(result[:data].last).to include('actual_values' => [], 'rcode' => 'NXDOMAIN')
          end
        end

        context 'when the domain is already verified' do
          let(:verified) { true }

          it 'stays indeterminate rather than demoting on one local negative' do
            result = strategy.validate_ownership(custom_domain)
            expect(result).to include(validated: nil, indeterminate: true, source: 'native')
            expect(result[:message]).to include('previously verified domain left unchanged')
          end

          it 'keeps both answers in :data for diagnosis' do
            result = strategy.validate_ownership(custom_domain)
            expect(result[:data].first['actual_values']).to be false
            expect(result[:data].last).to include('actual_values' => [], 'rcode' => 'NXDOMAIN')
          end
        end

        it 'does not issue a NXDOMAIN probe' do
          expect(Onetime::DomainValidation::ApproximatedClient)
            .to receive(:check_records_match_exactly).once.and_return(primary_response)
          strategy.validate_ownership(custom_domain)
        end
      end

      context 'and the native lookup answers NOERROR without TXT data' do
        let(:native_rcode) { Resolv::DNS::RCode::NoError }

        it 'fails definitively' do
          expect(strategy.validate_ownership(custom_domain)).to include(validated: false, source: 'native')
        end
      end

      context 'and the native lookup returns the value among others' do
        let(:native_rcode) { Resolv::DNS::RCode::NoError }
        let(:native_values) { %w[validation123 other] }

        it 'fails definitively (exactly-one semantics preserved)' do
          result = strategy.validate_ownership(custom_domain)
          expect(result[:validated]).to be false
          expect(result[:message]).to include('mismatch (2 value(s) found')
        end
      end

      context 'and the domain has no challenge value' do
        let(:custom_domain) do
          double('CustomDomain', display_domain: 'example.com', txt_validation_value: nil,
                                 validation_record: '_onetime-challenge-abc123.example.com')
        end

        it 'stays indeterminate (the verifier never looked, so nothing demotes)' do
          expect(resolver).not_to receive(:lookup)
          expect(strategy.validate_ownership(custom_domain)).to include(validated: nil, indeterminate: true)
        end
      end
    end

    context 'when the 200 payload carries no records' do
      before do
        allow(Onetime::DomainValidation::ApproximatedClient).to receive(:check_records_match_exactly)
          .and_return(double('Response', code: 200, parsed_response: {}))
        allow(OT).to receive(:lw)
      end

      it 'is not read as a mismatch: the native lookup decides' do
        result = strategy.validate_ownership(custom_domain)
        expect(result).to include(validated: false, source: 'native')
        expect(result[:data]).to contain_exactly(hash_including('rcode' => 'NXDOMAIN'))
      end

      context 'and the native lookup is indeterminate' do
        let(:native_rcode) { Resolv::DNS::RCode::ServFail }

        it 'is indeterminate' do
          expect(strategy.validate_ownership(custom_domain)[:validated]).to be_nil
        end
      end
    end

    context 'when API call fails' do
      let(:api_response) do
        double('Response',
               code: 500,
               parsed_response: { 'error' => 'Server error' })
      end

      before do
        allow(Onetime::DomainValidation::ApproximatedClient).to receive(:check_records_match_exactly)
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
        allow(Onetime::DomainValidation::ApproximatedClient).to receive(:check_records_match_exactly)
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
        allow(Onetime::DomainValidation::Features).to receive(:api_key).and_return(nil)
      end

      it 'returns error status' do
        result = strategy.request_certificate(custom_domain)
        expect(result[:status]).to eq('error')
      end
    end

    context 'when vhost creation returns 200 (existing vhost)' do
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
        allow(Onetime::DomainValidation::ApproximatedClient).to receive(:create_vhost)
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

    context 'when vhost creation returns 201 (new vhost created)' do
      let(:api_response) do
        double('Response',
               code: 201,
               parsed_response: {
                 'data' => {
                   'status' => 'PENDING',
                   'incoming_address' => 'example.com'
                 }
               })
      end

      before do
        allow(Onetime::DomainValidation::ApproximatedClient).to receive(:create_vhost)
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
        allow(Onetime::DomainValidation::ApproximatedClient).to receive(:create_vhost)
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
        allow(Onetime::DomainValidation::Features).to receive(:api_key).and_return(nil)
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
        allow(Onetime::DomainValidation::ApproximatedClient).to receive(:get_vhost_by_incoming_address)
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
        allow(Onetime::DomainValidation::ApproximatedClient).to receive(:get_vhost_by_incoming_address)
          .and_return(api_response)
      end

      it 'returns ready false' do
        result = strategy.check_status(custom_domain)
        expect(result[:ready]).to be false
      end
    end

    # Hosts fronted by another proxy (e.g. a Cloudflare CNAME setup) report
    # ACTIVE_SSL_PROXIED: DNS points elsewhere but requests reach the cluster
    # and the certificate is active.
    context 'when domain is active behind another proxy' do
      before do
        allow(Onetime::DomainValidation::ApproximatedClient).to receive(:get_vhost_by_incoming_address)
          .and_return(double('Response', code: 200, parsed_response: {
            'data' => { 'status' => 'ACTIVE_SSL_PROXIED', 'has_ssl' => true, 'is_resolving' => true }
          }))
      end

      it 'returns ready true' do
        expect(strategy.check_status(custom_domain)[:ready]).to be true
      end
    end

    # UNKNOWN = Approximated cannot determine a reliable status right now.
    context 'when status is UNKNOWN' do
      before do
        allow(Onetime::DomainValidation::ApproximatedClient).to receive(:get_vhost_by_incoming_address)
          .and_return(double('Response', code: 200, parsed_response: {
            'data' => { 'status' => 'UNKNOWN', 'has_ssl' => false, 'is_resolving' => false }
          }))
      end

      it 'reports is_resolving nil so the stored flag is left alone' do
        result = strategy.check_status(custom_domain)
        expect(result[:is_resolving]).to be_nil
        expect(result[:ready]).to be false
        expect(result[:status]).to eq('UNKNOWN')
      end
    end
  end
end

RSpec.describe Onetime::DomainValidation::PassthroughStrategy do
  let(:config) { {} }
  let(:strategy) { described_class.new(config) }
  let(:custom_domain) { double('CustomDomain', display_domain: 'example.com') }

  describe '#bulk_rate_limit' do
    it 'declares no pacing' do
      expect(strategy.bulk_rate_limit).to eq(0)
    end
  end

  describe '#proves_ownership?' do
    it 'is false: every domain passes without a lookup' do
      expect(strategy.proves_ownership?).to be(false)
    end

    it 'is false for a strategy that does not say otherwise' do
      expect(Class.new(Onetime::DomainValidation::BaseStrategy).new.proves_ownership?).to be(false)
    end
  end

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
  let(:answer_class) { Onetime::DomainValidation::TxtResolver::Answer }
  let(:resolver) { instance_double(Onetime::DomainValidation::TxtResolver, close: nil) }
  # The real verifier over a fake resolver: the three outcomes are exercised
  # through the real classification and no example opens a socket.
  let(:txt_verifier) { Onetime::DomainValidation::TxtVerifier.new(resolver_factory: -> { resolver }) }
  let(:strategy) { described_class.new(config, txt_verifier: txt_verifier) }
  let(:custom_domain) do
    double('CustomDomain',
           display_domain: 'example.com',
           txt_validation_value: 'validation123',
           validation_record: '_onetime-challenge-abc123.example.com',
           verified: verified,
           verified_confirmed_at: verified_confirmed_at,
           parse_vhost: stored_vhost)
  end
  let(:stored_vhost) { {} }
  let(:verified) { false }
  let(:verified_confirmed_at) { nil }

  def stub_lookup(rcode, values = [])
    allow(resolver).to receive(:lookup)
      .with(custom_domain.validation_record)
      .and_return(answer_class.new(rcode: rcode, values: values))
  end

  before { allow(OT).to receive(:lw) }

  describe '#bulk_rate_limit' do
    it 'declares no pacing for its own lookups' do
      expect(strategy.bulk_rate_limit).to eq(0)
    end
  end

  describe '#proves_ownership?' do
    it 'is true: a pass means the TXT record was found' do
      expect(strategy.proves_ownership?).to be(true)
    end
  end

  describe '#validate_ownership' do
    subject(:result) { strategy.validate_ownership(custom_domain) }

    it 'defaults to a TxtVerifier' do
      expect(described_class.new(config).txt_verifier).to be_a(Onetime::DomainValidation::TxtVerifier)
    end

    context 'with exactly one TXT value equal to the challenge' do
      before { stub_lookup(Resolv::DNS::RCode::NoError, ['validation123']) }

      it 'validates from the native lookup' do
        expect(result).to include(validated: true, source: 'native', mode: 'caddy_on_demand')
      end

      it 'carries :data so VerifyDomain persists the outcome' do
        expect(result[:data]).to contain_exactly(hash_including('match' => true, 'actual_values' => ['validation123']))
      end
    end

    context 'when the record does not exist (NXDOMAIN)' do
      before { stub_lookup(Resolv::DNS::RCode::NXDomain) }

      it 'is a definitive failure' do
        expect(result).to include(validated: false, message: 'TXT record not found', mode: 'caddy_on_demand')
        expect(result).not_to have_key(:indeterminate)
        expect(result[:data]).to contain_exactly(hash_including('actual_values' => [], 'rcode' => 'NXDOMAIN'))
      end
    end

    context 'when the name exists without TXT data (NOERROR, empty answer)' do
      before { stub_lookup(Resolv::DNS::RCode::NoError) }

      it 'is a definitive failure' do
        expect(result).to include(validated: false, message: 'TXT record not found')
      end
    end

    context 'when the TXT value differs from the challenge' do
      before { stub_lookup(Resolv::DNS::RCode::NoError, ['something-else']) }

      it 'is a definitive failure reported as a mismatch' do
        expect(result[:validated]).to be false
        expect(result[:message]).to include('mismatch (1 value(s) found')
      end
    end

    context 'when the challenge is present among other values' do
      before { stub_lookup(Resolv::DNS::RCode::NoError, %w[validation123 other]) }

      it 'fails (exactly one matching value required, as with Approximated)' do
        expect(result[:validated]).to be false
        expect(result[:message]).to include('mismatch (2 value(s) found')
      end
    end

    context 'when the resolver answers SERVFAIL' do
      before { stub_lookup(Resolv::DNS::RCode::ServFail) }

      it 'is indeterminate, never a failure' do
        expect(result).to include(validated: nil, indeterminate: true, mode: 'caddy_on_demand')
        expect(result[:message]).to include('SERVFAIL')
      end
    end

    context 'when the lookup times out' do
      before do
        allow(resolver).to receive(:lookup)
          .and_raise(Onetime::DomainValidation::TxtResolver::NoReplyError, 'no reply')
      end

      it 'is indeterminate' do
        expect(result).to include(validated: nil, indeterminate: true)
      end
    end

    # `verified` set before this strategy checked anything: there is no
    # earlier TXT proof for an indeterminate lookup to protect.
    context 'when the domain is verified but no TXT check ever confirmed it' do
      let(:verified) { true }

      it 'turns an indeterminate lookup into a definitive failure' do
        stub_lookup(Resolv::DNS::RCode::ServFail)

        expect(result).to include(validated: false, mode: 'caddy_on_demand', source: 'native')
        expect(result).not_to have_key(:indeterminate)
        expect(result[:message]).to match(/has not been confirmed by a TXT check .*SERVFAIL/)
        expect(result[:data]).to contain_exactly(hash_including('actual_values' => false))
      end

      it 'does the same when the failure is our own' do
        allow(custom_domain).to receive(:validation_record).and_raise(StandardError, 'boom')
        allow(OT).to receive(:le)

        expect(result).to include(validated: false, mode: 'caddy_on_demand')
        expect(result).not_to have_key(:indeterminate)
      end

      it 'still validates when the record is found' do
        stub_lookup(Resolv::DNS::RCode::NoError, ['validation123'])

        expect(result).to include(validated: true)
      end
    end

    context 'when the domain is verified and a TXT check has confirmed it' do
      let(:verified) { true }
      let(:verified_confirmed_at) { 1_789_000_000 }

      it 'keeps an indeterminate lookup indeterminate, so verified is held' do
        stub_lookup(Resolv::DNS::RCode::ServFail)

        expect(result).to include(validated: nil, indeterminate: true)
      end
    end

    context 'when the domain has no challenge value' do
      let(:custom_domain) do
        double('CustomDomain', display_domain: 'example.com', txt_validation_value: nil,
                               validation_record: '_onetime-challenge-abc123.example.com')
      end

      it 'fails without a lookup' do
        expect(resolver).not_to receive(:lookup)
        expect(result).to include(validated: false, mode: 'caddy_on_demand')
      end
    end

    context 'when the domain cannot produce its validation record' do
      before do
        allow(custom_domain).to receive(:validation_record).and_raise(StandardError, 'boom')
        allow(OT).to receive(:le)
      end

      it 'logs and stays indeterminate' do
        expect(result).to include(validated: nil, indeterminate: true, mode: 'caddy_on_demand')
        expect(OT).to have_received(:le).with(/Error validating example.com/)
      end
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
    subject(:result) { strategy.check_status(custom_domain) }

    let(:probe_result_class) { Onetime::DomainValidation::TlsProbe::Result }
    let(:tls_probe) { instance_double(Onetime::DomainValidation::TlsProbe) }
    let(:strategy) { described_class.new(config, txt_verifier: txt_verifier, tls_probe: tls_probe) }

    def stub_probe(**attrs)
      allow(tls_probe).to receive(:probe)
        .with('example.com')
        .and_return(probe_result_class.new(message: 'probe message', **attrs))
    end

    it 'defaults to a TlsProbe' do
      expect(described_class.new(config).tls_probe).to be_a(Onetime::DomainValidation::TlsProbe)
    end

    context 'when the domain resolves and presents a valid certificate' do
      let(:certificate) do
        instance_double(OpenSSL::X509::Certificate,
                        not_before: Time.utc(2026, 9, 1), not_after: Time.utc(2026, 11, 30))
      end

      before do
        stub_probe(is_resolving: true, has_ssl: true, addresses: ['93.184.216.34'],
                   connected_to: '93.184.216.34', certificate: certificate)
      end

      it 'is ready, resolving and has SSL' do
        expect(result).to include(ready: true, is_resolving: true, has_ssl: true, mode: 'caddy_on_demand')
      end

      it 'returns a string-keyed vhost payload for the domain pages' do
        expect(result[:data]).to include(
          'incoming_address' => 'example.com',
          'status' => 'ACTIVE_SSL',
          'has_ssl' => true,
          'is_resolving' => true,
          'dns_pointed_at' => '93.184.216.34',
          'ssl_active_from' => '2026-09-01T00:00:00Z',
          'ssl_active_until' => '2026-11-30T00:00:00Z',
          'source' => 'tls_probe',
        )
        expect(result[:data]['last_monitored_unix']).to be_a(Integer)
        expect { result[:data].to_json }.not_to raise_error
      end
    end

    context 'when the record still holds an Approximated vhost blob' do
      let(:stored_vhost) { { 'id' => 123, 'incoming_address' => 'example.com', 'status' => 'ACTIVE_SSL' } }

      before { stub_probe(is_resolving: true, has_ssl: false, addresses: ['93.184.216.34']) }

      it 'replaces stale UI state while retaining the cleanup obligation' do
        expect(result).to include(is_resolving: true, has_ssl: false, mode: 'caddy_on_demand')
        expect(result[:data]).to include(
          'status' => 'PENDING_SSL',
          'has_ssl' => false,
          'source' => 'tls_probe',
          'approximated_vhost_pending_cleanup' => true,
        )
        expect(result[:data]).not_to have_key('id')
      end

      context 'when certificate status is unknown but resolving is known' do
        before { stub_probe(is_resolving: true, has_ssl: nil, addresses: ['10.0.0.5']) }

        it 'does not present the stale active status as a successful probe' do
          expect(result).to include(is_resolving: true, has_ssl: nil, mode: 'caddy_on_demand')
          expect(result[:data]).to include(
            'status' => 'PENDING_SSL',
            'source' => 'tls_probe',
            'approximated_vhost_pending_cleanup' => true,
          )
          expect(result[:data]).not_to have_key('has_ssl')
        end
      end
    end

    context 'when the stored blob is an earlier probe result' do
      let(:stored_vhost) { { 'source' => 'tls_probe', 'has_ssl' => false } }

      before { stub_probe(is_resolving: true, has_ssl: false, addresses: ['93.184.216.34']) }

      it 'replaces it' do
        expect(result[:data]).to include('source' => 'tls_probe', 'status' => 'PENDING_SSL')
      end
    end

    context 'when an earlier probe retained an Approximated cleanup marker' do
      let(:stored_vhost) do
        { 'source' => 'tls_probe', 'has_ssl' => false, 'approximated_vhost_pending_cleanup' => true }
      end

      before { stub_probe(is_resolving: true, has_ssl: false, addresses: ['93.184.216.34']) }

      it 'keeps the marker on the refreshed probe payload' do
        expect(result[:data]['approximated_vhost_pending_cleanup']).to be true
      end
    end

    context 'when the domain resolves without a valid certificate' do
      before { stub_probe(is_resolving: true, has_ssl: false, addresses: ['93.184.216.34']) }

      it 'is resolving but not ready' do
        expect(result).to include(ready: false, is_resolving: true, has_ssl: false, mode: 'caddy_on_demand')
        expect(result[:data]).to include('status' => 'PENDING_SSL', 'has_ssl' => false)
        expect(result[:data]).not_to have_key('ssl_active_until')
      end
    end

    context 'when the domain does not resolve' do
      before { stub_probe(is_resolving: false, has_ssl: false) }

      it 'reports both as false' do
        expect(result).to include(ready: false, is_resolving: false, has_ssl: false, mode: 'caddy_on_demand')
        expect(result[:data]).to include('status' => 'DNS_INCORRECT', 'is_resolving' => false)
      end
    end

    context 'when the domain resolves but the certificate could not be checked' do
      before { stub_probe(is_resolving: true, has_ssl: nil, addresses: ['10.0.0.5']) }

      it 'reports resolving with has_ssl unknown' do
        expect(result).to include(ready: false, is_resolving: true, has_ssl: nil, mode: 'caddy_on_demand')
      end

      context 'with nothing stored yet' do
        it 'writes a blob that says resolving and makes no has_ssl claim' do
          expect(result[:data]).to include('status' => 'PENDING_SSL', 'is_resolving' => true, 'source' => 'tls_probe')
          expect(result[:data]).not_to have_key('has_ssl')
        end
      end

      # Checked once before its A record existed, then from a host that cannot
      # reach port 443 on it: `resolving` becomes true, and the blob the UI
      # reads must not go on saying DNS_INCORRECT.
      context 'with a stored blob from before the name resolved' do
        let(:stored_vhost) do
          { 'source' => 'tls_probe', 'status' => 'DNS_INCORRECT', 'is_resolving' => false, 'has_ssl' => false }
        end

        it 'refreshes status and is_resolving and leaves has_ssl as stored' do
          expect(result[:data]).to include('status' => 'PENDING_SSL', 'is_resolving' => true, 'has_ssl' => false)
          expect(result[:data]['last_monitored_unix']).to be_a(Integer)
        end
      end

      context 'with a stored blob that recorded a valid certificate' do
        let(:stored_vhost) do
          { 'source' => 'tls_probe', 'status' => 'ACTIVE_SSL', 'is_resolving' => true, 'has_ssl' => true,
            'ssl_active_from' => '2026-09-01T00:00:00Z', 'ssl_active_until' => '2026-11-30T00:00:00Z' }
        end

        it 'carries has_ssl and the certificate dates forward' do
          expect(result[:data]).to include(
            'status' => 'ACTIVE_SSL',
            'has_ssl' => true,
            'ssl_active_from' => '2026-09-01T00:00:00Z',
            'ssl_active_until' => '2026-11-30T00:00:00Z',
          )
        end
      end

      context 'with an Approximated vhost blob stored' do
        let(:stored_vhost) { { 'id' => 123, 'status' => 'ACTIVE_SSL' } }

        it 'leaves the blob for the cleanup chore' do
          expect(result).not_to have_key(:data)
        end
      end
    end

    context 'when the probe could not tell anything' do
      before { stub_probe(is_resolving: nil, has_ssl: nil) }

      it 'returns neither :mode nor :data, so VerifyDomain stores nothing' do
        expect(result).to include(ready: false, is_resolving: nil, has_ssl: nil, message: 'probe message')
        expect(result).not_to have_key(:mode)
        expect(result).not_to have_key(:data)
      end
    end

    context 'when the probe raises' do
      before do
        allow(tls_probe).to receive(:probe).and_raise(RuntimeError, 'boom')
        allow(OT).to receive(:le)
      end

      it 'is indeterminate and logged' do
        expect(result).to include(ready: false, is_resolving: nil, has_ssl: nil)
        expect(result).not_to have_key(:mode)
        expect(OT).to have_received(:le).with(/Error checking status for example\.com: RuntimeError: boom/)
      end
    end
  end
end

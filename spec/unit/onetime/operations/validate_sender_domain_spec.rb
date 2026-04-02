# spec/unit/onetime/operations/validate_sender_domain_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/operations/validate_sender_domain'

RSpec.describe Onetime::Operations::ValidateSenderDomain do
  let(:mock_custom_domain) do
    double(
      'CustomDomain',
      display_domain: 'example.com',
    )
  end

  let(:mailer_config) do
    double(
      'MailerConfig',
      domain_id: 'cd:test123',
      provider: 'ses',
      effective_provider: 'ses',
      from_address: 'sender@example.com',
      custom_domain: mock_custom_domain,
      'verification_status=' => nil,
      'verified_at=' => nil,
      'dns_records=' => nil,
      'updated=' => nil,
      'errors=' => nil,
      save: true,
      verification_status: 'pending',
    )
  end

  let(:dns_records) do
    [
      { type: 'TXT', name: '_dkim.example.com', verified: true },
      { type: 'TXT', name: '_spf.example.com', verified: true },
    ]
  end

  let(:mock_strategy) do
    instance_double(
      Onetime::DomainValidation::SenderStrategies::BaseStrategy,
      verify_dns_records: dns_records,
    )
  end

  before do
    allow(Onetime::CustomDomain).to receive(:find_by_identifier).and_return(mock_custom_domain)
    # Stub the instance method from the included module
    allow_any_instance_of(described_class).to receive(:check_dns_rate_limit!).and_return({ allowed: true, remaining: 9 })
  end

  # ==========================================================================
  # bypass_cache parameter tests
  # ==========================================================================

  describe 'bypass_cache parameter' do
    it 'passes bypass_cache: true to strategy.verify_dns_records' do
      operation = described_class.new(
        mailer_config: mailer_config,
        strategy: mock_strategy,
        persist: false,
        bypass_cache: true,
      )

      operation.call

      expect(mock_strategy).to have_received(:verify_dns_records).with(mailer_config, bypass_cache: true)
    end

    it 'passes bypass_cache: false to strategy.verify_dns_records' do
      operation = described_class.new(
        mailer_config: mailer_config,
        strategy: mock_strategy,
        persist: false,
        bypass_cache: false,
      )

      operation.call

      expect(mock_strategy).to have_received(:verify_dns_records).with(mailer_config, bypass_cache: false)
    end

    it 'defaults to bypass_cache: false when not specified' do
      operation = described_class.new(
        mailer_config: mailer_config,
        strategy: mock_strategy,
        persist: false,
      )

      operation.call

      expect(mock_strategy).to have_received(:verify_dns_records).with(mailer_config, bypass_cache: false)
    end
  end

  # ==========================================================================
  # Result structure
  # ==========================================================================

  describe 'Result' do
    let(:result) do
      described_class::Result.new(
        domain: 'example.com',
        provider: 'ses',
        dns_records: dns_records,
        all_verified: true,
        verification_status: 'verified',
        verified_at: Time.now,
        persisted: false,
        error: nil,
        rate_limit: { remaining: 9, reset_in: 3600 },
      )
    end

    it 'is a Data subclass (immutable)' do
      expect(result).to be_frozen
    end

    it 'exposes all_verified attribute' do
      expect(result.all_verified).to be true
    end

    it 'aliases success? based on error being nil' do
      expect(result.success?).to be true
    end
  end

  # ==========================================================================
  # Rate limit tracking
  # ==========================================================================

  describe 'rate limit tracking' do
    let(:rate_limit_exception) do
      Onetime::LimitExceeded.new(
        'DNS verification rate limit exceeded',
        retry_after: 3600,
        attempts: 10,
        max_attempts: 10,
      )
    end

    before do
      allow_any_instance_of(described_class).to receive(:check_dns_rate_limit!).and_raise(rate_limit_exception)
    end

    context 'with persist: true' do
      before do
        allow(mailer_config).to receive(:record_check_attempt)
      end

      it 'records check attempt when rate limited' do
        operation = described_class.new(
          mailer_config: mailer_config,
          strategy: mock_strategy,
          persist: true,
        )

        operation.call

        expect(mailer_config).to have_received(:record_check_attempt).with(
          0,
          a_string_matching(/Rate limited.*retry after 3600s/),
        )
      end

      it 'records duration_ms as 0 for rate-limited attempts' do
        operation = described_class.new(
          mailer_config: mailer_config,
          strategy: mock_strategy,
          persist: true,
        )

        operation.call

        expect(mailer_config).to have_received(:record_check_attempt).with(0, anything)
      end
    end

    context 'with persist: false' do
      it 'does not record check attempt when rate limited' do
        allow(mailer_config).to receive(:record_check_attempt)

        operation = described_class.new(
          mailer_config: mailer_config,
          strategy: mock_strategy,
          persist: false,
        )

        operation.call

        expect(mailer_config).not_to have_received(:record_check_attempt)
      end
    end

    it 'returns rate_limited verification_status' do
      operation = described_class.new(
        mailer_config: mailer_config,
        strategy: mock_strategy,
        persist: false,
      )

      result = operation.call

      expect(result.verification_status).to eq('rate_limited')
    end

    it 'includes rate limit details in result' do
      operation = described_class.new(
        mailer_config: mailer_config,
        strategy: mock_strategy,
        persist: false,
      )

      result = operation.call

      expect(result.rate_limit).to include(
        remaining: 0,
        reset_in: 3600,
        current: 10,
        limit: 10,
      )
    end

    it 'does not call strategy.verify_dns_records when rate limited' do
      operation = described_class.new(
        mailer_config: mailer_config,
        strategy: mock_strategy,
        persist: false,
      )

      operation.call

      expect(mock_strategy).not_to have_received(:verify_dns_records)
    end
  end
end

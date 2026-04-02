# spec/unit/onetime/domain_validation/sender_strategies/lettermint_validation_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/domain_validation/sender_strategies/base_strategy'
require 'onetime/domain_validation/sender_strategies/lettermint_validation'

RSpec.describe Onetime::DomainValidation::SenderStrategies::LettermintValidation do
  let(:strategy) { described_class.new }
  let(:custom_domain) do
    instance_double('Onetime::CustomDomain', display_domain: 'example.com')
  end
  let(:mailer_config) do
    instance_double(
      'Onetime::CustomDomain::MailerConfig',
      from_address: 'sender@example.com',
      provider: 'lettermint',
      custom_domain: custom_domain
    )
  end

  describe '#strategy_name' do
    it 'returns lettermint' do
      expect(strategy.strategy_name).to eq('lettermint')
    end
  end

  describe '.accepted_options' do
    it 'returns array of accepted option keys' do
      expect(described_class.accepted_options).to eq([:dkim_selectors, :spf_cname_prefix, :spf_cname_target])
    end
  end

  describe 'constants' do
    it 'defines DKIM_SELECTORS as lm1 and lm2' do
      expect(described_class::DKIM_SELECTORS).to eq(%w[lm1 lm2])
    end

    it 'defines SPF_CNAME_PREFIX as lm-bounces' do
      expect(described_class::SPF_CNAME_PREFIX).to eq('lm-bounces')
    end

    it 'defines SPF_CNAME_TARGET as bounces.lmta.net' do
      expect(described_class::SPF_CNAME_TARGET).to eq('bounces.lmta.net')
    end
  end

  describe '#initialize' do
    context 'with default options' do
      it 'uses default DKIM selectors' do
        records = strategy.required_dns_records(mailer_config)
        dkim_records = records.select { |r| r[:host].include?('_domainkey') }
        expect(dkim_records.size).to eq(2)
      end
    end

    context 'with custom DKIM selectors' do
      let(:strategy) { described_class.new(dkim_selectors: %w[custom1 custom2 custom3]) }

      it 'uses custom DKIM selectors' do
        records = strategy.required_dns_records(mailer_config)
        dkim_records = records.select { |r| r[:host].include?('_domainkey') }
        expect(dkim_records.size).to eq(3)
        expect(dkim_records.map { |r| r[:host] }).to include(
          'custom1._domainkey.example.com',
          'custom2._domainkey.example.com',
          'custom3._domainkey.example.com'
        )
      end
    end

    context 'with custom spf_cname_prefix' do
      let(:strategy) { described_class.new(spf_cname_prefix: 'custom-bounces') }

      it 'uses custom SPF CNAME prefix in host' do
        records = strategy.required_dns_records(mailer_config)
        spf_record = records.find { |r| r[:host].include?('bounces') }
        expect(spf_record[:host]).to eq('custom-bounces.example.com')
      end
    end

    context 'with custom spf_cname_target' do
      let(:strategy) { described_class.new(spf_cname_target: 'custom.bounces.example.net') }

      it 'uses custom SPF CNAME target in value' do
        records = strategy.required_dns_records(mailer_config)
        spf_record = records.find { |r| r[:host].start_with?('lm-bounces') }
        expect(spf_record[:value]).to eq('custom.bounces.example.net')
      end
    end
  end

  describe '#required_dns_records' do
    subject(:records) { strategy.required_dns_records(mailer_config) }

    it 'returns an array' do
      expect(records).to be_an(Array)
    end

    it 'returns exactly 3 records (2 DKIM + 1 SPF bounce)' do
      expect(records.size).to eq(3)
    end

    describe 'DKIM records' do
      subject(:dkim_records) { records.select { |r| r[:host].include?('_domainkey') } }

      it 'returns 2 DKIM CNAME records' do
        expect(dkim_records.size).to eq(2)
        expect(dkim_records.all? { |r| r[:type] == 'CNAME' }).to be true
      end

      it 'has correct host format for lm1 selector' do
        lm1 = dkim_records.find { |r| r[:host].start_with?('lm1') }
        expect(lm1[:host]).to eq('lm1._domainkey.example.com')
      end

      it 'has correct host format for lm2 selector' do
        lm2 = dkim_records.find { |r| r[:host].start_with?('lm2') }
        expect(lm2[:host]).to eq('lm2._domainkey.example.com')
      end

      it 'has correct value pointing to lettermint DKIM server' do
        lm1 = dkim_records.find { |r| r[:host].start_with?('lm1') }
        expect(lm1[:value]).to eq('lm1.dkim.lettermint.com')
      end

      it 'includes purpose description' do
        expect(dkim_records.first[:purpose]).to match(/DKIM signature/)
      end
    end

    describe 'SPF bounce CNAME record' do
      subject(:spf_record) { records.find { |r| r[:host].start_with?('lm-bounces') } }

      it 'returns CNAME type for SPF (not TXT)' do
        expect(spf_record[:type]).to eq('CNAME')
      end

      it 'has correct host format: lm-bounces.{domain}' do
        expect(spf_record[:host]).to eq('lm-bounces.example.com')
      end

      it 'has correct value pointing to bounces.lmta.net' do
        expect(spf_record[:value]).to eq('bounces.lmta.net')
      end

      it 'includes purpose description' do
        expect(spf_record[:purpose]).to eq('SPF/Return-Path (bounce handling)')
      end
    end

    context 'with different domains' do
      let(:custom_domain) do
        instance_double('Onetime::CustomDomain', display_domain: 'mycompany.co.uk')
      end
      let(:mailer_config) do
        instance_double(
          'Onetime::CustomDomain::MailerConfig',
          from_address: 'noreply@mycompany.co.uk',
          provider: 'lettermint',
          custom_domain: custom_domain
        )
      end

      it 'extracts domain correctly from custom_domain' do
        dkim_record = records.find { |r| r[:host].include?('_domainkey') }
        expect(dkim_record[:host]).to eq('lm1._domainkey.mycompany.co.uk')
      end

      it 'uses correct domain for SPF bounce CNAME' do
        spf_record = records.find { |r| r[:host].start_with?('lm-bounces') }
        expect(spf_record[:host]).to eq('lm-bounces.mycompany.co.uk')
      end
    end

    context 'when domain has subdomain' do
      let(:custom_domain) do
        instance_double('Onetime::CustomDomain', display_domain: 'mail.example.com')
      end
      let(:mailer_config) do
        instance_double(
          'Onetime::CustomDomain::MailerConfig',
          from_address: 'noreply@mail.example.com',
          provider: 'lettermint',
          custom_domain: custom_domain
        )
      end

      it 'uses the full domain including subdomain' do
        dkim_record = records.find { |r| r[:host].include?('_domainkey') }
        expect(dkim_record[:host]).to eq('lm1._domainkey.mail.example.com')
      end
    end
  end

  describe '#verify_dns_records' do
    let(:mock_redis) { instance_double('Redis') }

    before do
      allow(Onetime::CustomDomain).to receive(:dbclient).and_return(mock_redis)
      allow(mock_redis).to receive(:get).and_return(nil)
      allow(mock_redis).to receive(:pipelined).and_return([nil, nil, nil])
    end

    it 'delegates to verify_all_records' do
      expect(strategy).to receive(:verify_all_records).with(mailer_config, bypass_cache: false)
      strategy.verify_dns_records(mailer_config)
    end

    it 'passes bypass_cache option through' do
      expect(strategy).to receive(:verify_all_records).with(mailer_config, bypass_cache: true)
      strategy.verify_dns_records(mailer_config, bypass_cache: true)
    end
  end

  describe 'DNS record structure comparison' do
    describe 'old TXT-based SPF (deprecated)' do
      # This test documents the old behavior that is being replaced
      it 'would have returned TXT record for SPF' do
        old_spf_record = {
          type: 'TXT',
          host: 'example.com',
          value: 'v=spf1 include:lettermint.com ~all',
          purpose: 'SPF authentication',
        }

        # The new implementation should NOT return this type of record
        records = strategy.required_dns_records(mailer_config)
        txt_records = records.select { |r| r[:type] == 'TXT' }
        expect(txt_records).to be_empty
      end
    end

    describe 'new CNAME-based SPF' do
      it 'returns CNAME for SPF bounce subdomain' do
        records = strategy.required_dns_records(mailer_config)
        spf_record = records.find { |r| r[:host].start_with?('lm-bounces') }

        expect(spf_record).to eq({
          type: 'CNAME',
          host: 'lm-bounces.example.com',
          value: 'bounces.lmta.net',
          purpose: 'SPF/Return-Path (bounce handling)',
        })
      end
    end

    describe 'complete record set for example.com' do
      it 'returns all expected DNS records' do
        records = strategy.required_dns_records(mailer_config)

        expect(records).to contain_exactly(
          {
            type: 'CNAME',
            host: 'lm1._domainkey.example.com',
            value: 'lm1.dkim.lettermint.com',
            purpose: 'DKIM signature 1 of 2',
          },
          {
            type: 'CNAME',
            host: 'lm2._domainkey.example.com',
            value: 'lm2.dkim.lettermint.com',
            purpose: 'DKIM signature 2 of 2',
          },
          {
            type: 'CNAME',
            host: 'lm-bounces.example.com',
            value: 'bounces.lmta.net',
            purpose: 'SPF/Return-Path (bounce handling)',
          }
        )
      end
    end
  end
end

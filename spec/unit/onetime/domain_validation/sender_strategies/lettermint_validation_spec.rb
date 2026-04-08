# spec/unit/onetime/domain_validation/sender_strategies/lettermint_validation_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/domain_validation/sender_strategies/base_strategy'
require 'onetime/domain_validation/sender_strategies/lettermint_validation'

RSpec.describe Onetime::DomainValidation::SenderStrategies::LettermintValidation do
  let(:strategy) { described_class.new }
  let(:domain) { 'example.com' }
  let(:custom_domain) do
    instance_double('Onetime::CustomDomain', display_domain: domain)
  end

  # Realistic Lettermint-provisioned DNS records (string-keyed hashes)
  let(:provisioned_dns_records) do
    [
      {'type' => 'TXT', 'name' => "lettermint._domainkey.#{domain}", 'value' => 'v=DKIM1;k=rsa;p=MIIBIjANBg...'},
      {'type' => 'CNAME', 'name' => "lm-bounces.#{domain}", 'value' => 'bounces.lmta.net'},
      {'type' => 'TXT', 'name' => "_dmarc.#{domain}", 'value' => 'v=DMARC1;p=none'},
    ]
  end

  let(:dns_records_field) { double(value: provisioned_dns_records) }

  let(:mailer_config) do
    instance_double(
      'Onetime::CustomDomain::MailerConfig',
      from_address: "sender@#{domain}",
      provider: 'lettermint',
      custom_domain: custom_domain,
      domain_id: "#{domain}:mailer",
      dns_records: dns_records_field
    )
  end

  describe '#strategy_name' do
    it 'returns lettermint' do
      expect(strategy.strategy_name).to eq('lettermint')
    end
  end

  describe '.accepted_options' do
    it 'returns empty array (options no longer configurable)' do
      expect(described_class.accepted_options).to eq([])
    end
  end

  describe '#required_dns_records' do
    subject(:records) { strategy.required_dns_records(mailer_config) }

    it 'returns an array' do
      expect(records).to be_an(Array)
    end

    it 'returns one record per provisioned DNS entry' do
      expect(records.size).to eq(3)
    end

    it 'maps provisioned records to symbol-keyed hashes' do
      records.each do |r|
        expect(r.keys).to contain_exactly(:type, :host, :value, :purpose)
      end
    end

    describe 'DKIM record' do
      subject(:dkim_record) { records.find { |r| r[:host].include?('_domainkey') } }

      it 'has correct type' do
        expect(dkim_record[:type]).to eq('TXT')
      end

      it 'has correct host from provisioned data' do
        expect(dkim_record[:host]).to eq("lettermint._domainkey.#{domain}")
      end

      it 'has correct value from provisioned data' do
        expect(dkim_record[:value]).to eq('v=DKIM1;k=rsa;p=MIIBIjANBg...')
      end

      it 'classifies purpose as DKIM' do
        expect(dkim_record[:purpose]).to eq('DKIM')
      end
    end

    describe 'bounce CNAME record' do
      subject(:bounce_record) { records.find { |r| r[:host].include?('lm-bounces') } }

      it 'has correct type' do
        expect(bounce_record[:type]).to eq('CNAME')
      end

      it 'has correct host from provisioned data' do
        expect(bounce_record[:host]).to eq("lm-bounces.#{domain}")
      end

      it 'has correct value from provisioned data' do
        expect(bounce_record[:value]).to eq('bounces.lmta.net')
      end

      it 'classifies purpose as SPF/Return-Path' do
        expect(bounce_record[:purpose]).to eq('SPF/Return-Path')
      end
    end

    describe 'DMARC record' do
      subject(:dmarc_record) { records.find { |r| r[:host].include?('_dmarc') } }

      it 'has correct type' do
        expect(dmarc_record[:type]).to eq('TXT')
      end

      it 'has correct host from provisioned data' do
        expect(dmarc_record[:host]).to eq("_dmarc.#{domain}")
      end

      it 'has correct value from provisioned data' do
        expect(dmarc_record[:value]).to eq('v=DMARC1;p=none')
      end

      it 'classifies purpose as DMARC' do
        expect(dmarc_record[:purpose]).to eq('DMARC')
      end
    end

    context 'when dns_records returns nil' do
      let(:mailer_config) do
        instance_double(
          'Onetime::CustomDomain::MailerConfig',
          from_address: "sender@#{domain}",
          provider: 'lettermint',
          custom_domain: custom_domain,
          domain_id: "#{domain}:mailer",
          dns_records: nil
        )
      end

      it 'returns empty array' do
        expect(records).to eq([])
      end
    end

    context 'when dns_records.value returns empty array' do
      let(:dns_records_field) { double(value: []) }

      it 'returns empty array' do
        expect(records).to eq([])
      end
    end

    context 'with different provisioned record sets' do
      let(:provisioned_dns_records) do
        [
          {'type' => 'CNAME', 'name' => "lm1._domainkey.#{domain}", 'value' => 'lm1.dkim.lettermint.com'},
          {'type' => 'CNAME', 'name' => "lm2._domainkey.#{domain}", 'value' => 'lm2.dkim.lettermint.com'},
          {'type' => 'CNAME', 'name' => "lm-bounces.#{domain}", 'value' => 'bounces.lmta.net'},
          {'type' => 'TXT', 'name' => "_dmarc.#{domain}", 'value' => 'v=DMARC1;p=quarantine'},
        ]
      end

      it 'maps all provisioned records regardless of count' do
        expect(records.size).to eq(4)
      end

      it 'produces two DKIM records when two are provisioned' do
        dkim_records = records.select { |r| r[:host].include?('_domainkey') }
        expect(dkim_records.size).to eq(2)
      end
    end

    context 'with a different domain' do
      let(:domain) { 'mycompany.co.uk' }

      it 'uses the domain from provisioned record names' do
        dkim_record = records.find { |r| r[:host].include?('_domainkey') }
        expect(dkim_record[:host]).to eq('lettermint._domainkey.mycompany.co.uk')
      end

      it 'uses the domain in bounce record' do
        bounce_record = records.find { |r| r[:host].include?('lm-bounces') }
        expect(bounce_record[:host]).to eq('lm-bounces.mycompany.co.uk')
      end
    end

    context 'with a subdomain' do
      let(:domain) { 'mail.example.com' }

      it 'uses the full subdomain from provisioned record names' do
        dkim_record = records.find { |r| r[:host].include?('_domainkey') }
        expect(dkim_record[:host]).to eq('lettermint._domainkey.mail.example.com')
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

  describe 'purpose classification' do
    it 'classifies SPF TXT records' do
      spf_records = [
        {'type' => 'TXT', 'name' => domain, 'value' => 'v=spf1 include:lettermint.com ~all'},
      ]
      allow(dns_records_field).to receive(:value).and_return(spf_records)

      records = strategy.required_dns_records(mailer_config)
      expect(records.first[:purpose]).to eq('SPF')
    end

    it 'classifies MX records' do
      mx_records = [
        {'type' => 'MX', 'name' => domain, 'value' => '10 mx.lettermint.com'},
      ]
      allow(dns_records_field).to receive(:value).and_return(mx_records)

      records = strategy.required_dns_records(mailer_config)
      expect(records.first[:purpose]).to eq('Inbound mail')
    end

    it 'falls back to record type for unrecognized patterns' do
      other_records = [
        {'type' => 'A', 'name' => domain, 'value' => '1.2.3.4'},
      ]
      allow(dns_records_field).to receive(:value).and_return(other_records)

      records = strategy.required_dns_records(mailer_config)
      expect(records.first[:purpose]).to eq('A')
    end
  end
end

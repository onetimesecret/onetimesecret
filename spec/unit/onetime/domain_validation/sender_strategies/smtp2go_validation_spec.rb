# spec/unit/onetime/domain_validation/sender_strategies/smtp2go_validation_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/domain_validation/sender_strategies/base_strategy'
require 'onetime/domain_validation/sender_strategies/smtp2go_validation'

RSpec.describe Onetime::DomainValidation::SenderStrategies::Smtp2goValidation do
  let(:strategy) { described_class.new }
  let(:domain) { 'example.com' }
  let(:custom_domain) do
    instance_double('Onetime::CustomDomain', display_domain: domain)
  end

  # Realistic SMTP2GO-provisioned DNS records (string-keyed hashes, as
  # normalized by Smtp2goSenderStrategy#build_dns_records)
  let(:provisioned_dns_records) do
    [
      {'type' => 'CNAME', 'name' => "em1234._domainkey.#{domain}", 'value' => 'dkim.smtp2go.net', 'status' => 'pending'},
      {'type' => 'CNAME', 'name' => "bounce.#{domain}", 'value' => 'return.smtp2go.net', 'status' => 'pending'},
      {'type' => 'CNAME', 'name' => "track.#{domain}", 'value' => 'track.smtp2go.net', 'status' => 'pending'},
    ]
  end

  let(:dns_records_field) { double(value: provisioned_dns_records) }

  let(:mailer_config) do
    instance_double(
      'Onetime::CustomDomain::MailerConfig',
      from_address: "sender@#{domain}",
      provider: 'smtp2go',
      custom_domain: custom_domain,
      domain_id: "#{domain}:mailer",
      dns_records: dns_records_field
    )
  end

  describe '#strategy_name' do
    it 'returns smtp2go' do
      expect(strategy.strategy_name).to eq('smtp2go')
    end
  end

  describe '.accepted_options' do
    it 'returns empty array (options not configurable)' do
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
        expect(dkim_record[:type]).to eq('CNAME')
      end

      it 'has correct host from provisioned data' do
        expect(dkim_record[:host]).to eq("em1234._domainkey.#{domain}")
      end

      it 'has correct value from provisioned data' do
        expect(dkim_record[:value]).to eq('dkim.smtp2go.net')
      end

      it 'classifies purpose as DKIM' do
        expect(dkim_record[:purpose]).to eq('DKIM')
      end
    end

    describe 'return-path CNAME record' do
      subject(:rpath_record) { records.find { |r| r[:value] == 'return.smtp2go.net' } }

      it 'has correct type' do
        expect(rpath_record[:type]).to eq('CNAME')
      end

      it 'has correct host from provisioned data' do
        expect(rpath_record[:host]).to eq("bounce.#{domain}")
      end

      it 'classifies purpose as SPF/Return-Path' do
        expect(rpath_record[:purpose]).to eq('SPF/Return-Path')
      end
    end

    describe 'tracking CNAME record' do
      subject(:tracking_record) { records.find { |r| r[:value] == 'track.smtp2go.net' } }

      it 'has correct type' do
        expect(tracking_record[:type]).to eq('CNAME')
      end

      it 'has correct host from provisioned data' do
        expect(tracking_record[:host]).to eq("track.#{domain}")
      end

      it 'classifies purpose as Tracking' do
        expect(tracking_record[:purpose]).to eq('Tracking')
      end
    end

    it 'upcases the record type' do
      allow(dns_records_field).to receive(:value).and_return([
        {'type' => 'cname', 'name' => "em1234._domainkey.#{domain}", 'value' => 'dkim.smtp2go.net'},
      ])

      expect(records.first[:type]).to eq('CNAME')
    end

    context 'when dns_records returns nil' do
      let(:mailer_config) do
        instance_double(
          'Onetime::CustomDomain::MailerConfig',
          from_address: "sender@#{domain}",
          provider: 'smtp2go',
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

    context 'with a different domain' do
      let(:domain) { 'mycompany.co.uk' }

      it 'uses the domain from provisioned record names' do
        dkim_record = records.find { |r| r[:host].include?('_domainkey') }
        expect(dkim_record[:host]).to eq('em1234._domainkey.mycompany.co.uk')
      end

      it 'uses the domain in the return-path record' do
        rpath_record = records.find { |r| r[:value] == 'return.smtp2go.net' }
        expect(rpath_record[:host]).to eq('bounce.mycompany.co.uk')
      end
    end

    context 'with a subdomain' do
      let(:domain) { 'mail.example.com' }

      it 'uses the full subdomain from provisioned record names' do
        dkim_record = records.find { |r| r[:host].include?('_domainkey') }
        expect(dkim_record[:host]).to eq('em1234._domainkey.mail.example.com')
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
    it 'classifies a bounce-prefixed CNAME with a custom target as SPF/Return-Path' do
      custom_records = [
        {'type' => 'CNAME', 'name' => "bounce.#{domain}", 'value' => 'custom-return.example.net'},
      ]
      allow(dns_records_field).to receive(:value).and_return(custom_records)

      records = strategy.required_dns_records(mailer_config)
      expect(records.first[:purpose]).to eq('SPF/Return-Path')
    end

    it 'classifies a custom return-path subdomain by its smtp2go target' do
      custom_records = [
        {'type' => 'CNAME', 'name' => "mail-bounce.#{domain}", 'value' => 'return.smtp2go.net'},
      ]
      allow(dns_records_field).to receive(:value).and_return(custom_records)

      records = strategy.required_dns_records(mailer_config)
      expect(records.first[:purpose]).to eq('SPF/Return-Path')
    end

    it 'classifies a custom tracking subdomain by its smtp2go target' do
      custom_records = [
        {'type' => 'CNAME', 'name' => "link.#{domain}", 'value' => 'track.smtp2go.net'},
      ]
      allow(dns_records_field).to receive(:value).and_return(custom_records)

      records = strategy.required_dns_records(mailer_config)
      expect(records.first[:purpose]).to eq('Tracking')
    end

    it 'classifies DMARC TXT records' do
      dmarc_records = [
        {'type' => 'TXT', 'name' => "_dmarc.#{domain}", 'value' => 'v=DMARC1;p=none'},
      ]
      allow(dns_records_field).to receive(:value).and_return(dmarc_records)

      records = strategy.required_dns_records(mailer_config)
      expect(records.first[:purpose]).to eq('DMARC')
    end

    it 'classifies SPF TXT records' do
      spf_records = [
        {'type' => 'TXT', 'name' => domain, 'value' => 'v=spf1 include:spf.smtp2go.com ~all'},
      ]
      allow(dns_records_field).to receive(:value).and_return(spf_records)

      records = strategy.required_dns_records(mailer_config)
      expect(records.first[:purpose]).to eq('SPF')
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

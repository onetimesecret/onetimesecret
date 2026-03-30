# spec/unit/onetime/operations/provision_sender_domain_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/operations/provision_sender_domain'

RSpec.describe Onetime::Operations::ProvisionSenderDomain do
  let(:mailer_config) do
    double(
      'MailerConfig',
      domain_id: 'cd:test123',
      provider: 'ses',
      from_address: 'sender@example.com',
      'provider_dns_data=' => nil,
      'updated=' => nil,
      save: true,
    )
  end

  let(:mock_credentials) do
    {
      access_key_id: 'AKIAIOSFODNN7EXAMPLE',
      secret_access_key: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
      region: 'us-east-1',
    }
  end

  let(:mock_strategy) do
    instance_double('SESSenderStrategy', strategy_name: 'ses')
  end

  before do
    allow(Onetime::Mail::Mailer).to receive(:provider_credentials).and_return(mock_credentials)
    allow(Onetime::Mail::SenderStrategies).to receive(:supports_provisioning?).with('ses').and_return(true)
    allow(Onetime::Mail::SenderStrategies).to receive(:for_provider).with('ses').and_return(mock_strategy)
  end

  # ==========================================================================
  # Result object
  # ==========================================================================

  describe 'Result' do
    let(:result) do
      described_class::Result.new(
        success: true,
        dns_records: [{ type: 'CNAME', name: 'a.example.com', value: 'b.example.com' }],
        provider_data: { region: 'us-east-1' },
        error: nil,
      )
    end

    it 'is a Data subclass (immutable)' do
      expect(result).to be_frozen
    end

    it 'implements success?' do
      expect(result.success?).to be true
    end

    it 'implements failed?' do
      expect(result.failed?).to be false
    end

    it 'converts to hash via to_h' do
      h = result.to_h
      expect(h).to include(:success, :dns_records, :provider_data, :error)
    end

    context 'when failed' do
      let(:failed_result) do
        described_class::Result.new(
          success: false, dns_records: [], provider_data: nil, error: 'bad'
        )
      end

      it 'reports failed? true and success? false' do
        expect(failed_result.success?).to be false
        expect(failed_result.failed?).to be true
      end
    end
  end

  # ==========================================================================
  # normalize_dns_records (the core fix from Items 1-3)
  # ==========================================================================

  describe '#normalize_dns_records (private)' do
    subject(:operation) { described_class.new(mailer_config: mailer_config, persist: false) }

    context 'when dns_data is an Array (standard strategy output)' do
      let(:array_data) do
        [
          { type: 'CNAME', name: 'abc._domainkey.example.com', value: 'abc.dkim.amazonses.com' },
          { type: 'CNAME', name: 'def._domainkey.example.com', value: 'def.dkim.amazonses.com' },
        ]
      end

      it 'passes Array through directly without transformation' do
        result = operation.send(:normalize_dns_records, array_data, 'ses')

        expect(result).to equal(array_data)
        expect(result.size).to eq(2)
      end

      it 'passes Lettermint Array through directly' do
        lm_data = [
          { type: 'CNAME', name: 'lm1._domainkey.example.com', value: 'lm1.dkim.lettermint.com' },
          { type: 'CNAME', name: 'lm2._domainkey.example.com', value: 'lm2.dkim.lettermint.com' },
        ]

        result = operation.send(:normalize_dns_records, lm_data, 'lettermint')

        expect(result).to equal(lm_data)
      end

      it 'passes SendGrid Array through directly' do
        sg_data = [
          { type: 'CNAME', name: 'em.example.com', value: 'u123.wl.sendgrid.net', purpose: 'mail_cname' },
          { type: 'CNAME', name: 's1._domainkey.example.com', value: 's1.domainkey.u123.wl.sendgrid.net', purpose: 'dkim1' },
        ]

        result = operation.send(:normalize_dns_records, sg_data, 'sendgrid')

        expect(result).to equal(sg_data)
      end

      it 'passes empty Array through' do
        result = operation.send(:normalize_dns_records, [], 'ses')

        expect(result).to eq([])
      end
    end

    context 'when dns_data is a Hash (legacy/fallback path)' do
      it 'normalizes SES Hash format with dkim_tokens' do
        hash_data = { dkim_tokens: %w[token1 token2], region: 'us-east-1' }

        result = operation.send(:normalize_dns_records, hash_data, 'ses')

        expect(result).to be_an(Array)
        expect(result.size).to eq(2)
        expect(result.first[:type]).to eq('CNAME')
        expect(result.first[:name]).to include('token1._domainkey')
      end

      it 'normalizes SendGrid Hash format with dns_records key' do
        hash_data = {
          dns_records: [
            { type: 'CNAME', name: 'em.example.com', value: 'sendgrid.net' },
          ],
        }

        result = operation.send(:normalize_dns_records, hash_data, 'sendgrid')

        expect(result).to be_an(Array)
        expect(result.size).to eq(1)
      end

      it 'normalizes Lettermint Hash format with records key' do
        hash_data = {
          records: [
            { type: 'CNAME', name: 'lm._domainkey.example.com', value: 'lm.dkim.lettermint.com' },
          ],
        }

        result = operation.send(:normalize_dns_records, hash_data, 'lettermint')

        expect(result).to be_an(Array)
        expect(result.size).to eq(1)
      end
    end

    context 'when dns_data is nil or unexpected type' do
      it 'returns empty array for nil' do
        result = operation.send(:normalize_dns_records, nil, 'ses')

        expect(result).to eq([])
      end

      it 'returns empty array for String' do
        result = operation.send(:normalize_dns_records, 'unexpected', 'ses')

        expect(result).to eq([])
      end

      it 'returns empty array for Integer' do
        result = operation.send(:normalize_dns_records, 42, 'ses')

        expect(result).to eq([])
      end
    end
  end

  # ==========================================================================
  # #call — full operation lifecycle
  # ==========================================================================

  describe '#call' do
    context 'happy path with mock strategy (persist: false)' do
      let(:provision_response) do
        {
          success: true,
          message: 'Domain provisioned',
          dns_records: [
            { type: 'CNAME', name: 'abc._domainkey.example.com', value: 'abc.dkim.amazonses.com' },
            { type: 'CNAME', name: 'def._domainkey.example.com', value: 'def.dkim.amazonses.com' },
          ],
          identity_id: 'example.com',
          provider_data: { dkim_tokens: %w[abc def], region: 'us-east-1' },
        }
      end

      before do
        allow(mock_strategy).to receive(:provision_dns_records).and_return(provision_response)
      end

      it 'returns success Result with dns_records' do
        result = described_class.new(
          mailer_config: mailer_config,
          strategy: mock_strategy,
          persist: false,
        ).call

        expect(result).to be_a(described_class::Result)
        expect(result.success?).to be true
        expect(result.dns_records.size).to eq(2)
        expect(result.error).to be_nil
      end

      it 'preserves Array dns_records from strategy' do
        result = described_class.new(
          mailer_config: mailer_config,
          strategy: mock_strategy,
          persist: false,
        ).call

        expect(result.dns_records).to be_an(Array)
        expect(result.dns_records.first[:type]).to eq('CNAME')
      end
    end

    context 'when strategy returns failure' do
      before do
        allow(mock_strategy).to receive(:provision_dns_records).and_return({
          success: false,
          error: 'Domain already authenticated',
          dns_records: [],
        })
      end

      it 'returns failed Result' do
        result = described_class.new(
          mailer_config: mailer_config,
          strategy: mock_strategy,
          persist: false,
        ).call

        expect(result.success?).to be false
        expect(result.error).to eq('Domain already authenticated')
        expect(result.dns_records).to eq([])
      end
    end

    context 'validation errors' do
      it 'fails when provider is empty' do
        config = double('MailerConfig', domain_id: 'cd:test', provider: '', from_address: 'a@b.com')

        result = described_class.new(mailer_config: config, persist: false).call

        expect(result.success?).to be false
        expect(result.error).to include('provider is required')
      end

      it 'fails when from_address is empty' do
        config = double('MailerConfig', domain_id: 'cd:test', provider: 'ses', from_address: '')

        result = described_class.new(mailer_config: config, persist: false).call

        expect(result.success?).to be false
        expect(result.error).to include('from_address is required')
      end

      it 'fails when mailer_config is nil' do
        result = described_class.new(mailer_config: nil, persist: false).call

        expect(result.success?).to be false
        expect(result.error).to include('mailer_config is required')
      end
    end

    context 'when provider does not support provisioning' do
      before do
        allow(Onetime::Mail::SenderStrategies).to receive(:supports_provisioning?)
          .with('smtp').and_return(false)
      end

      it 'returns failure for SMTP' do
        config = double('MailerConfig', domain_id: 'cd:test', provider: 'smtp', from_address: 'a@b.com')

        result = described_class.new(mailer_config: config, persist: false).call

        expect(result.success?).to be false
        expect(result.error).to include('does not support automated DNS provisioning')
      end
    end

    context 'when credentials fail to load' do
      before do
        allow(Onetime::Mail::Mailer).to receive(:provider_credentials).and_return(nil)
      end

      it 'returns failure with credential error' do
        result = described_class.new(
          mailer_config: mailer_config,
          persist: false,
        ).call

        expect(result.success?).to be false
        expect(result.error).to include('Failed to load credentials')
      end
    end
  end

  # ==========================================================================
  # persist_provider_data — Item 5 (error propagation)
  # ==========================================================================

  describe '#persist_provider_data (private)' do
    let(:provision_response) do
      {
        success: true,
        dns_records: [{ type: 'CNAME', name: 'a.example.com', value: 'b.example.com' }],
        identity_id: 'example.com',
        provider_data: {},
      }
    end

    before do
      allow(mock_strategy).to receive(:provision_dns_records).and_return(provision_response)
    end

    context 'when persistence succeeds' do
      it 'saves provider_dns_data to mailer_config' do
        expect(mailer_config).to receive(:provider_dns_data=)
        expect(mailer_config).to receive(:dns_records=)
        expect(mailer_config).to receive(:updated=)
        expect(mailer_config).to receive(:save)

        described_class.new(
          mailer_config: mailer_config,
          strategy: mock_strategy,
          persist: true,
        ).call
      end
    end

    context 'when persist: false' do
      it 'does not call save' do
        expect(mailer_config).not_to receive(:save)

        described_class.new(
          mailer_config: mailer_config,
          strategy: mock_strategy,
          persist: false,
        ).call
      end
    end

    context 'when persistence raises (Item 5 fix)' do
      before do
        allow(mailer_config).to receive(:provider_dns_data=)
        allow(mailer_config).to receive(:dns_records=)
        allow(mailer_config).to receive(:updated=)
        allow(mailer_config).to receive(:save).and_raise(StandardError, 'Redis connection refused')
      end

      it 'propagates error into Result (no longer silently swallowed)' do
        result = described_class.new(
          mailer_config: mailer_config,
          strategy: mock_strategy,
          persist: true,
        ).call

        expect(result.success?).to be false
        expect(result.error).to include('Redis connection refused')
      end

      it 'does not return success when save fails' do
        result = described_class.new(
          mailer_config: mailer_config,
          strategy: mock_strategy,
          persist: true,
        ).call

        # The old behavior would have returned success: true here.
        # The fix ensures the StandardError propagates to the rescue block
        # in #call and is wrapped in a failure Result.
        expect(result.success).to be false
      end
    end
  end
end

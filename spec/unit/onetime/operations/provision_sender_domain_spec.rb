# spec/unit/onetime/operations/provision_sender_domain_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'onetime/operations/provision_sender_domain'

RSpec.describe Onetime::Operations::ProvisionSenderDomain do
  let(:mock_lock) do
    double('Lock', acquire: 'mock-token', release: true,
      dbkey: 'sender-identity-lock', dbclient: double('Redis', eval: 1))
  end

  let(:mailer_config) do
    double(
      'MailerConfig',
      domain_id: 'cd:test123',
      provider: 'ses',
      effective_provider: 'ses',
      from_address: 'sender@example.com',
      sender_identity_lock: mock_lock,
      'provider_dns_data=' => nil,
      'dns_records=' => nil,
      'updated=' => nil,
    )
  end

  let(:mock_credentials) do
    {
      'access_key_id' => 'AKIAIOSFODNN7EXAMPLE',
      'secret_access_key' => 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
      'region' => 'us-east-1',
    }
  end

  let(:mock_strategy) do
    instance_double('SESSenderStrategy', strategy_name: 'ses')
  end

  before do
    allow(Onetime::Mail::Mailer).to receive(:provider_credentials).and_return(mock_credentials)
    allow(Onetime::Mail::SenderStrategies).to receive(:supports_provisioning?).with('ses').and_return(true)
    allow(Onetime::Mail::SenderStrategies).to receive(:for_provider).with('ses').and_return(mock_strategy)
    allow(Onetime::CustomDomain::MailerConfig).to receive(:exists_for_domain?).and_return(true)
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
        config = double('MailerConfig', domain_id: 'cd:test', provider: '', effective_provider: '', from_address: 'a@b.com')

        result = described_class.new(mailer_config: config, persist: false).call

        expect(result.success?).to be false
        expect(result.error).to include('provider could not be resolved')
      end

      it 'fails when from_address is empty' do
        config = double('MailerConfig', domain_id: 'cd:test', provider: 'ses', effective_provider: 'ses', from_address: '')

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

    context 'when ownership is lost during the provider call' do
      [0, IOError.new('renewal unavailable')].each do |renewal_failure|
        it "fails without persisting provider data on #{renewal_failure.inspect}" do
          allow(mock_strategy).to receive(:provision_dns_records) do
            if renewal_failure.is_a?(Exception)
              allow(mock_lock.dbclient).to receive(:eval).and_raise(renewal_failure)
            else
              allow(mock_lock.dbclient).to receive(:eval).and_return(renewal_failure)
            end
            { success: true, dns_records: [], provider_data: { identity_id: 'example.com' } }
          end
          expect(Onetime::CustomDomain::MailerConfig).not_to receive(:record_job_result!)

          result = described_class.new(mailer_config: mailer_config, strategy: mock_strategy).call

          expect(result.success?).to be false
          expect(result.error).to include('lock lost', 'provider state may have changed')
          expect(mock_lock).to have_received(:release).with('mock-token')
        end
      end
    end

    context 'with a real renewable lease', :datastore do
      let(:mock_lock) do
        Onetime::CustomDomain::MailerConfig.sender_identity_lock("provision-lease-#{SecureRandom.hex(8)}")
      end

      before do
        stub_const('Onetime::Operations::SenderIdentityLease::TTL', 1)
        stub_const('Onetime::Operations::SenderIdentityLease::RENEW_INTERVAL', 0.05)
      end

      after { mock_lock.force_unlock! }

      it 'excludes teardown beyond the initial TTL through provider calls and persistence' do
        token = nil
        allow(mock_strategy).to receive(:provision_dns_records) do
          token = mock_lock.value
          sleep 1.2
          expect(mock_lock.held_by?(token)).to be true
          expect(mock_lock.acquire(ttl: 1)).to be false
          { success: true, dns_records: [], provider_data: {} }
        end
        allow(Onetime::CustomDomain::MailerConfig).to receive(:record_job_result!) do |*_args, &block|
          sleep 1.2
          expect(mock_lock.held_by?(token)).to be true
          expect(mock_lock.acquire(ttl: 1)).to be false
          [mailer_config, block.call(mailer_config)]
        end

        result = described_class.new(mailer_config: mailer_config, strategy: mock_strategy).call

        expect(result.success?).to be true
        expect(mock_lock.locked?).to be false
      end

      it 'does not persist or report success after watchdog failure during provisioning' do
        client = mock_lock.dbclient
        allow(mock_lock).to receive(:dbclient).and_return(client)
        allow(client).to receive(:eval).and_call_original
        attempted = Queue.new
        allow(mock_strategy).to receive(:provision_dns_records) do
          allow(client).to receive(:eval)
            .with(Onetime::Operations::SenderIdentityLease::RENEW_SCRIPT, [mock_lock.dbkey], anything) do
              attempted << true
              raise IOError, 'renewal unavailable'
            end
          Timeout.timeout(3) { attempted.pop }
          allow(client).to receive(:eval)
            .with(Onetime::Operations::SenderIdentityLease::RENEW_SCRIPT, [mock_lock.dbkey], anything).and_return(1)
          { success: true, dns_records: [], provider_data: {} }
        end
        expect(Onetime::CustomDomain::MailerConfig).not_to receive(:record_job_result!)

        result = described_class.new(mailer_config: mailer_config, strategy: mock_strategy).call

        expect(result.success?).to be false
        expect(result.error).to include('lock lost', 'renewal failed')
        expect(mock_lock.locked?).to be false
      end
    end

    context 'when the sender identity lock is held' do
      let(:mock_lock) { double('Lock', acquire: false) }

      it 'fails without calling the provider' do
        result = described_class.new(mailer_config: mailer_config, strategy: mock_strategy, persist: false).call

        expect(result.success?).to be false
        expect(result.error).to include('already in progress')
        expect(Onetime::Mail::Mailer).not_to have_received(:provider_credentials)
      end
    end

    # A sender config delete or a domain removal that finished between the
    # record's load and the lock has torn the identity down and deleted the
    # record; registering the identity now would leave nothing pointing to it.
    context 'when the record was deleted before the lock was taken' do
      before do
        allow(Onetime::CustomDomain::MailerConfig).to receive(:exists_for_domain?)
          .with('cd:test123').and_return(false)
      end

      it 'fails without calling the provider and releases the lock' do
        result = described_class.new(mailer_config: mailer_config, strategy: mock_strategy, persist: false).call

        expect(result.success?).to be false
        expect(result.error).to include('was deleted before provisioning')
        expect(Onetime::Mail::Mailer).not_to have_received(:provider_credentials)
        expect(mock_lock).to have_received(:release).with('mock-token')
      end
    end

    context 'when provider does not support provisioning' do
      before do
        allow(Onetime::Mail::SenderStrategies).to receive(:supports_provisioning?)
          .with('smtp').and_return(false)
      end

      it 'returns failure for SMTP' do
        config = double('MailerConfig', domain_id: 'cd:test', provider: 'smtp', effective_provider: 'smtp', from_address: 'a@b.com', sender_identity_lock: mock_lock)

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
      it 'saves provider_dns_data to the stored record' do
        allow(Onetime::CustomDomain::MailerConfig).to receive(:record_job_result!)
          .with('cd:test123', 'sender@example.com') { |*_args, &block| [mailer_config, block.call(mailer_config)] }
        expect(mailer_config).to receive(:provider_dns_data=)
        expect(mailer_config).to receive(:dns_records=)
        expect(mailer_config).to receive(:updated=)

        described_class.new(
          mailer_config: mailer_config,
          strategy: mock_strategy,
          persist: true,
        ).call
      end
    end

    context 'when persist: false' do
      it 'does not write the config' do
        expect(Onetime::CustomDomain::MailerConfig).not_to receive(:record_job_result!)

        described_class.new(
          mailer_config: mailer_config,
          strategy: mock_strategy,
          persist: false,
        ).call
      end
    end

    context 'when persistence raises (Item 5 fix)' do
      before do
        allow(Onetime::CustomDomain::MailerConfig).to receive(:record_job_result!)
          .and_raise(StandardError, 'Redis connection refused')
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

    # A DELETE (or an address change) during the provider calls: the data
    # belongs to no stored record, so nothing is written and the run fails.
    context 'when the record was deleted or changed its address meanwhile' do
      before do
        allow(Onetime::CustomDomain::MailerConfig).to receive(:record_job_result!).and_return(nil)
      end

      it 'writes nothing and returns a failure' do
        expect(mailer_config).not_to receive(:provider_dns_data=)

        result = described_class.new(mailer_config: mailer_config, strategy: mock_strategy, persist: true).call

        expect(result.success?).to be false
        expect(result.error).to include('deleted or changed its address during provisioning')
      end
    end
  end
end

# apps/api/domains/spec/logic/sender_config/send_test_email_spec.rb
#
# frozen_string_literal: true

# Unit tests for SenderConfig::SendTestEmail ColonelAuditEvent.record coverage.
#
# The send_test_email flow calls ColonelAuditEvent.record to persist test email
# events to the audit trail. These specs verify:
#   - On success: verb 'domain_sender.test_email_sent', result :success
#   - On failure: result :failure, error_code in detail
#
# RUN (lane runner only — a raw rspec/rake invocation inherits the dev
# shell's env and can reach dev data; see AGENTS.md "Running tests"):
#   tests/lanes/run api --only apps/api/domains/spec/logic/sender_config/send_test_email_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'
require 'onetime/models/colonel_audit_event'

RSpec.describe DomainsAPI::Logic::SenderConfig::SendTestEmail do
  let(:customer) do
    instance_double(
      Onetime::Customer,
      custid: 'cust123',
      objid: 'cust123',
      extid: 'ext-cust123',
      email: 'user@example.com',
      anonymous?: false,
      verified?: true,
    )
  end

  let(:custom_domain) do
    instance_double(
      Onetime::CustomDomain,
      identifier: 'domain123',
      extid: 'ext-domain123',
      display_domain: 'example.com',
      org_id: 'org123',
    )
  end

  let(:organization) do
    instance_double(
      Onetime::Organization,
      objid: 'org123',
      extid: 'ext-org123',
      display_name: 'Test Org',
    )
  end

  let(:mailer_config) do
    instance_double(
      Onetime::CustomDomain::MailerConfig,
      from_address: 'noreply@example.com',
      from_name: 'Test Sender',
      reply_to: 'reply@example.com',
      effective_provider: 'smtp2go',
      api_key: 'test-api-key',
    )
  end

  let(:session) { { 'authenticated' => true, 'csrf' => 'test-csrf-token' } }
  let(:strategy_result) do
    double('StrategyResult', session: session, user: customer, authenticated?: true, metadata: {})
  end

  let(:params) { { 'extid' => 'ext-domain123' } }
  let(:logic) { described_class.new(strategy_result, params) }

  # Stub for the delivery backend
  let(:mock_backend) { double('DeliveryBackend') }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)

    # Bypass authorization and set up ivars directly
    allow(logic).to receive(:authorize_sender_config!) do
      logic.instance_variable_set(:@custom_domain, custom_domain)
      logic.instance_variable_set(:@organization, organization)
    end

    allow(Onetime::CustomDomain::MailerConfig).to receive(:find_by_domain_id)
      .with('domain123')
      .and_return(mailer_config)

    # Stub the audit event recording
    allow(Onetime::ColonelAuditEvent).to receive(:record)
  end

  describe '#process (audit trail)' do
    context 'when test email succeeds' do
      before do
        allow(logic).to receive(:build_test_backend).and_return(mock_backend)
        allow(mock_backend).to receive(:deliver).and_return(true)
      end

      it 'calls ColonelAuditEvent.record with result: :success' do
        logic.raise_concerns
        logic.process

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: customer,
          verb: 'domain_sender.test_email_sent',
          target: 'domain123',
          result: :success,
          detail: hash_including(
            recipient: 'user@example.com',
            from_address: 'noreply@example.com',
            provider: 'smtp2go',
          ),
        )
      end

      it 'does not include error_code in detail on success' do
        logic.raise_concerns
        logic.process

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_excluding(detail: hash_including(:error_code)),
        )
      end
    end

    context 'when test email fails with delivery error' do
      let(:delivery_error) do
        error = Onetime::Mail::DeliveryError.new('Connection refused')
        allow(error).to receive(:transient?).and_return(false)
        allow(error).to receive(:original_error).and_return(nil)
        error
      end

      before do
        allow(logic).to receive(:build_test_backend).and_return(mock_backend)
        allow(mock_backend).to receive(:deliver).and_raise(delivery_error)
      end

      it 'calls ColonelAuditEvent.record with result: :failure' do
        logic.raise_concerns
        logic.process

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          actor: customer,
          verb: 'domain_sender.test_email_sent',
          target: 'domain123',
          result: :failure,
          detail: hash_including(
            recipient: 'user@example.com',
            from_address: 'noreply@example.com',
            provider: 'smtp2go',
            error_code: 'delivery_failed',
          ),
        )
      end
    end

    context 'when test email fails with transient error' do
      let(:transient_error) do
        error = Onetime::Mail::DeliveryError.new('Temporary failure')
        allow(error).to receive(:transient?).and_return(true)
        allow(error).to receive(:original_error).and_return(nil)
        error
      end

      before do
        allow(logic).to receive(:build_test_backend).and_return(mock_backend)
        allow(mock_backend).to receive(:deliver).and_raise(transient_error)
      end

      it 'records transient_error as error_code' do
        logic.raise_concerns
        logic.process

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(
            result: :failure,
            detail: hash_including(error_code: 'transient_error'),
          ),
        )
      end
    end

    context 'when test email fails with unexpected error' do
      before do
        allow(logic).to receive(:build_test_backend).and_return(mock_backend)
        allow(mock_backend).to receive(:deliver).and_raise(StandardError, 'Something broke')
      end

      it 'records unexpected_error as error_code' do
        logic.raise_concerns
        logic.process

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(
            result: :failure,
            detail: hash_including(error_code: 'unexpected_error'),
          ),
        )
      end
    end

    context 'when domain not provisioned on provider' do
      let(:domain_not_found_error) do
        error = Onetime::Mail::DeliveryError.new('Domain not found')
        allow(error).to receive(:transient?).and_return(false)
        original = double('OriginalError', status_code: 422, message: 'Domain not found')
        allow(Lettermint::HttpRequestError).to receive(:===).and_return(false) if defined?(Lettermint::HttpRequestError)
        allow(error).to receive(:original_error).and_return(original)
        error
      end

      before do
        # Simulate Lettermint 422 error (domain not provisioned)
        stub_const('Lettermint::HttpRequestError', Class.new(StandardError))
        allow(logic).to receive(:build_test_backend).and_return(mock_backend)
        allow(mock_backend).to receive(:deliver).and_raise(domain_not_found_error)
        allow(domain_not_found_error.original_error).to receive(:is_a?)
          .with(Lettermint::HttpRequestError).and_return(true)
      end

      it 'records domain_not_provisioned as error_code' do
        logic.raise_concerns
        logic.process

        expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
          hash_including(
            result: :failure,
            detail: hash_including(error_code: 'domain_not_provisioned'),
          ),
        )
      end
    end
  end
end

# apps/api/domains/spec/logic/sender_config/validate_sender_config_spec.rb
#
# frozen_string_literal: true

# Unit tests for SenderConfig::ValidateSenderConfig#raise_concerns (issue #4047).
#
# Regression guard: validation must be rejected up front when the mailer
# config has no provisioned DNS records. Without the guard, process would
# clear verification state and enqueue both workers with nothing to check —
# and DnsRecordCheckWorker's empty result set used to read as verified.
#
# RUN:
#   pnpm run test:rspec apps/api/domains/spec/logic/sender_config/validate_sender_config_spec.rb

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require_relative '../../../../../../apps/api/domains/application'

RSpec.describe DomainsAPI::Logic::SenderConfig::ValidateSenderConfig do
  let(:owner) do
    instance_double(
      Onetime::Customer,
      custid: 'owner123',
      objid: 'owner123',
      extid: 'ext-owner123',
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
    instance_double(Onetime::Organization, objid: 'org123', extid: 'ext-org123', display_name: 'Test Org')
  end

  let(:session) { { 'authenticated' => true, 'csrf' => 'test-csrf-token' } }
  let(:strategy_result) do
    double('StrategyResult', session: session, user: owner, authenticated?: true, metadata: {})
  end

  # The route is /:extid/email-config/validate, so the logic reads params['extid'].
  let(:params) { { 'extid' => 'ext-domain123' } }
  let(:logic) { described_class.new(strategy_result, params) }

  let(:from_address) { 'noreply@example.com' }
  let(:mailer_config) do
    instance_double(
      Onetime::CustomDomain::MailerConfig,
      from_address: from_address,
      provisioned?: provisioned,
    )
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)

    # Bypass the (separately tested) authorization step; just set the ivars it
    # would populate so raise_concerns can proceed to the mailer_config checks.
    allow(logic).to receive(:authorize_sender_config!) do
      logic.instance_variable_set(:@custom_domain, custom_domain)
      logic.instance_variable_set(:@organization, organization)
    end
    allow(Onetime::CustomDomain::MailerConfig).to receive(:find_by_domain_id)
      .with('domain123').and_return(mailer_config)
  end

  context 'when the mailer config is not provisioned' do
    let(:provisioned) { false }

    it 'rejects validation with a form error before any state is touched' do
      expect { logic.raise_concerns }.to raise_error(OT::FormError) do |ex|
        expect(ex.message).to match(/provisioned/i)
        expect(ex.field).to eq(:domain_id)
        expect(ex.error_type).to eq(:invalid)
      end
    end
  end

  context 'when the mailer config is provisioned' do
    let(:provisioned) { true }

    it 'passes raise_concerns' do
      expect { logic.raise_concerns }.not_to raise_error
    end
  end

  context 'when from_address is missing' do
    let(:provisioned) { false }
    let(:from_address) { '' }

    it 'reports the missing from_address before the provisioned check' do
      expect { logic.raise_concerns }.to raise_error(OT::FormError) do |ex|
        expect(ex.field).to eq(:from_address)
        expect(ex.error_type).to eq(:missing)
      end
    end
  end

  context 'when no mailer config exists for the domain' do
    let(:mailer_config) { nil }

    it 'reports the missing sender configuration' do
      expect { logic.raise_concerns }.to raise_error(OT::FormError) do |ex|
        expect(ex.message).to match(/no sender configuration/i)
        expect(ex.field).to eq(:domain_id)
        expect(ex.error_type).to eq(:missing)
      end
    end
  end

  # process: the reset and its rollback run against the record as stored
  # (GuardedConfigWrites). The guarded class methods are faked here so the
  # real condition and block run against an unsaved MailerConfig standing in
  # for the stored record; nothing touches the datastore.
  describe '#process rollback' do
    let(:provisioned) { true }
    let(:model) { Onetime::CustomDomain::MailerConfig }
    let(:lifecycle) { Onetime::Jobs::Workers::JobLifecycle }
    let(:lock) { instance_double(Familia::Lock, acquire: 'token', release: true) }
    let(:dns_check_results) { double('dns_check_results', value: [{ 'value_matches' => true }]) }

    # The record before the reset: a completed, verified run.
    let(:stored_before) do
      model.new(
        domain_id: 'domain123',
        from_address: from_address,
        verification_status: 'verified',
        dns_check_status: lifecycle::COMPLETED,
        dns_verified: 'true',
        dns_check_completed_at: '100',
        provider_check_status: lifecycle::COMPLETED,
        provider_verified: 'true',
        provider_check_completed_at: '200',
      )
    end

    # The record the rollback reads: what the reset wrote, as moved on by
    # whichever jobs started in between (overridden per example).
    let(:moved_on) { {} }
    let(:stored_at_rollback) do
      reset = {
        domain_id: 'domain123',
        from_address: from_address,
        verification_status: 'pending',
        dns_check_status: lifecycle::QUEUED,
        dns_verified: nil,
        dns_check_completed_at: '',
        provider_check_status: lifecycle::QUEUED,
        provider_verified: nil,
        provider_check_completed_at: '',
      }
      model.new(**reset, **moved_on)
    end

    let(:rollback_calls) { [] }

    before do
      logic.instance_variable_set(:@custom_domain, custom_domain)
      logic.instance_variable_set(:@organization, organization)
      allow(Familia::Lock).to receive(:new).and_return(lock)
      allow(stored_before).to receive(:dns_check_results).and_return(dns_check_results)
      allow(dns_check_results).to receive(:value=)

      allow(model).to receive(:update_for_domain!).with('domain123') do |&blk|
        [stored_before, blk.call(stored_before)]
      end
      allow(model).to receive(:update_for_domain_if).with('domain123', kind_of(Proc)) do |_id, condition, &blk|
        rollback_calls << condition
        next nil unless condition.call(stored_at_rollback)

        [stored_at_rollback, blk.call(stored_at_rollback)]
      end

      allow(Onetime::Jobs::Publisher).to receive(:enqueue_dns_record_check).and_return(true)
      allow(Onetime::Jobs::Publisher).to receive(:enqueue_domain_validation).and_raise(StandardError, 'broker down')
    end

    def run_process
      expect { logic.process }.to raise_error(StandardError, 'broker down')
    end

    context 'when neither job started before the second enqueue failed' do
      it 'restores every reset field, including verification_status' do
        run_process

        expect(stored_at_rollback.verification_status).to eq('verified')
        expect(stored_at_rollback.dns_check_status).to eq(lifecycle::COMPLETED)
        expect(stored_at_rollback.dns_verified).to eq('true')
        expect(stored_at_rollback.dns_check_completed_at).to eq('100')
        expect(stored_at_rollback.provider_check_status).to eq(lifecycle::COMPLETED)
        expect(stored_at_rollback.provider_verified).to eq('true')
        expect(stored_at_rollback.provider_check_completed_at).to eq('200')
      end

      it 'restores the DNS job results' do
        run_process

        expect(dns_check_results).to have_received(:value=).with(nil).ordered
        expect(dns_check_results).to have_received(:value=).with([{ 'value_matches' => true }]).ordered
      end
    end

    context 'when the DNS job already completed (inline, or a fast worker)' do
      let(:moved_on) do
        { dns_check_status: lifecycle::COMPLETED, dns_verified: 'false', dns_check_completed_at: '300' }
      end

      it 'keeps the DNS result, restores the never-enqueued provider job, and derives the status' do
        run_process

        expect(stored_at_rollback.dns_check_status).to eq(lifecycle::COMPLETED)
        expect(stored_at_rollback.dns_verified).to eq('false')
        expect(stored_at_rollback.dns_check_completed_at).to eq('300')
        expect(stored_at_rollback.provider_check_status).to eq(lifecycle::COMPLETED)
        expect(stored_at_rollback.provider_verified).to eq('true')
        expect(stored_at_rollback.provider_check_completed_at).to eq('200')
        # Both terminal now: derived from the fresh DNS result and the prior provider result.
        expect(stored_at_rollback.verification_status).to eq('failed')
      end

      it 'does not put the old DNS results back over the new ones' do
        run_process

        expect(dns_check_results).to have_received(:value=).with(nil).once
        expect(dns_check_results).not_to have_received(:value=).with([{ 'value_matches' => true }])
      end
    end

    context 'when the DNS job is processing' do
      let(:moved_on) { { dns_check_status: lifecycle::PROCESSING } }

      it 'leaves verification_status pending for the live job to settle' do
        run_process

        expect(stored_at_rollback.dns_check_status).to eq(lifecycle::PROCESSING)
        expect(stored_at_rollback.provider_check_status).to eq(lifecycle::COMPLETED)
        expect(stored_at_rollback.verification_status).to eq('pending')
      end
    end

    context 'when both jobs moved on' do
      let(:moved_on) { { dns_check_status: lifecycle::PROCESSING, provider_check_status: lifecycle::PROCESSING } }

      it 'writes nothing' do
        run_process

        expect(rollback_calls.size).to eq(1)
        expect(rollback_calls.first.call(stored_at_rollback)).to be(false)
        expect(stored_at_rollback.provider_check_status).to eq(lifecycle::PROCESSING)
        expect(dns_check_results).to have_received(:value=).with(nil).once
      end
    end

    context 'when the record was deleted meanwhile' do
      before do
        allow(model).to receive(:update_for_domain_if).with('domain123', kind_of(Proc)).and_return(nil)
      end

      it 're-raises without recreating anything' do
        run_process

        expect(model).to have_received(:update_for_domain_if).once
        expect(dns_check_results).to have_received(:value=).with(nil).once
      end
    end

    context 'when the reset itself failed' do
      before do
        allow(model).to receive(:update_for_domain!).and_raise(Familia::KeyNotFoundError, 'gone')
      end

      it 'reports a conflict and does not roll back' do
        expect { logic.process }.to raise_error(OT::FormError) { |ex| expect(ex.error_type).to eq(:conflict) }
        expect(model).not_to have_received(:update_for_domain_if)
      end
    end
  end
end

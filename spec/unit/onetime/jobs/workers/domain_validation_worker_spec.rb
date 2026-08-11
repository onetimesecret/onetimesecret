# spec/unit/onetime/jobs/workers/domain_validation_worker_spec.rb
#
# frozen_string_literal: true

# Unit tests for DomainValidationWorker's provider_verified persistence.
#
# Regression: sender strategies used to return verified: false on ANY error
# (rotated/revoked API key, 401/5xx, transport failure), which the worker
# persisted as provider_verified = false — silently demoting a previously
# VERIFIED custom sender domain to failed on the next scheduled check.
#
# The contract is now tri-state: strategies return verified: nil when the
# answer could not be determined, and the worker must leave the stored
# provider_verified untouched in that case (excluded from save_fields),
# mirroring what its outer rescue path already did. DNS fallback applies
# ONLY when the check never ran at all (no credentials / smtp provider) —
# distinguished by provider_result being nil, not by the verified value.
#
# Seams: same pattern as dns_record_check_worker_spec — the worker is
# instantiated for real, trace context yields straight through, the
# idempotency claim is granted, MailerConfig lookup / operation / strategy
# return doubles, and the logger is a null object.

require 'spec_helper'
require 'onetime/jobs/workers/domain_validation_worker'
require 'onetime/mail/sender_strategies'

RSpec.describe Onetime::Jobs::Workers::DomainValidationWorker do
  let(:worker) { described_class.new }

  let(:delivery_info) do
    double('DeliveryInfo', delivery_tag: 1, routing_key: described_class::QUEUE_NAME, redelivered?: false)
  end
  let(:amqp_metadata) { double('MessageProperties', message_id: 'msg-provider-tristate', headers: nil) }
  let(:msg) { { domain_id: 'domain-abc', requested_at: '2026-08-11T00:00:00Z' }.to_json }

  let(:provider_dns_data_key) { double('provider_dns_data', value: {}, :value= => nil) }
  let(:mailer_config) do
    double(
      'MailerConfig',
      effective_provider: 'smtp2go',
      provider_dns_data: provider_dns_data_key,
      provider_verified: 'true', # previously verified (stored value)
      :provider_verified= => nil,
      :provider_check_status= => nil,
      :provider_check_completed_at= => nil,
      :last_error= => nil,
      :updated= => nil,
      save_fields: true,
      refresh!: true,
      jobs_completed?: false,
      dns_check_status: 'processing',
    )
  end

  # DNS validation result from ValidateSenderDomain (the operation the worker
  # runs before the provider check). all_verified drives the degraded-mode
  # fallback when no provider check ran.
  let(:dns_result) do
    double(
      'Result',
      error: nil,
      verification_status: 'verified',
      all_verified: true,
      persisted: false,
    )
  end

  let(:strategy) { double('SenderStrategy') }
  let(:credentials) { { 'api_key' => 'api-key' } }

  before do
    allow(worker).to receive(:logger).and_return(double('logger').as_null_object)
    allow(worker).to receive(:with_trace_context).and_yield
    allow(worker).to receive(:claim_for_processing).and_return(true)
    allow(Onetime::CustomDomain::MailerConfig).to receive(:find_by_domain_id)
      .with('domain-abc').and_return(mailer_config)
    allow(Onetime::Operations::ValidateSenderDomain).to receive(:new)
      .and_return(double('Operation', call: dns_result))
    allow(Onetime::Mail::SenderStrategies).to receive(:for_provider)
      .with('smtp2go').and_return(strategy)
    allow(Onetime::Mail::Mailer).to receive(:provider_credentials)
      .with('smtp2go').and_return(credentials)
  end

  def work
    worker.work_with_params(msg, delivery_info, amqp_metadata)
  end

  describe 'provider_verified persistence (tri-state contract)' do
    context 'when the provider check is inconclusive (verified: nil, e.g. rotated key)' do
      before do
        allow(strategy).to receive(:check_provider_verification_status)
          .with(mailer_config, credentials: credentials)
          .and_return(verified: nil, status: 'error', message: 'Verification check failed: HTTP 401')
      end

      it 'never touches provider_verified — a rotated key must not demote a verified domain' do
        expect(work).to eq(:ack)
        expect(mailer_config).not_to have_received(:provider_verified=)
      end

      it 'excludes provider_verified from save_fields' do
        work
        expect(mailer_config).to have_received(:save_fields)
          .with(:provider_check_status, :provider_check_completed_at, :last_error, :updated)
      end

      it 'records an inconclusive last_error and still completes the job' do
        work
        expect(mailer_config).to have_received(:last_error=)
          .with('Provider check inconclusive: Verification check failed: HTTP 401')
        expect(mailer_config).to have_received(:provider_check_status=)
          .with(Onetime::Jobs::Workers::JobLifecycle::COMPLETED)
        expect(mailer_config).to have_received(:provider_check_completed_at=)
      end
    end

    context 'when the provider answers authoritatively false (not_found)' do
      before do
        allow(strategy).to receive(:check_provider_verification_status)
          .with(mailer_config, credentials: credentials)
          .and_return(verified: false, status: 'not_found', message: 'Domain not found')
      end

      it 'persists provider_verified = false with the provider status in last_error' do
        expect(work).to eq(:ack)
        expect(mailer_config).to have_received(:provider_verified=).with(false)
        expect(mailer_config).to have_received(:last_error=).with('Provider status: not_found')
        expect(mailer_config).to have_received(:save_fields)
          .with(:provider_verified, :provider_check_status, :provider_check_completed_at, :last_error, :updated)
      end
    end

    context 'when the provider answers verified: true' do
      before do
        allow(strategy).to receive(:check_provider_verification_status)
          .with(mailer_config, credentials: credentials)
          .and_return(verified: true, status: 'verified', message: 'Domain verified')
      end

      it 'persists provider_verified = true and clears last_error' do
        expect(work).to eq(:ack)
        expect(mailer_config).to have_received(:provider_verified=).with(true)
        expect(mailer_config).to have_received(:last_error=).with(nil)
      end
    end

    context 'when the check never ran (no credentials configured)' do
      let(:credentials) { {} }

      before do
        allow(strategy).to receive(:check_provider_verification_status)
      end

      it 'falls back to the DNS result (degraded mode) rather than preserving' do
        expect(work).to eq(:ack)
        expect(strategy).not_to have_received(:check_provider_verification_status)
        expect(mailer_config).to have_received(:provider_verified=).with(true) # dns_result.all_verified
        expect(mailer_config).to have_received(:last_error=).with(nil)
        expect(mailer_config).to have_received(:save_fields)
          .with(:provider_verified, :provider_check_status, :provider_check_completed_at, :last_error, :updated)
      end
    end
  end
end

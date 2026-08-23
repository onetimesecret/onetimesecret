# spec/unit/onetime/jobs/workers/dns_record_check_worker_spec.rb
#
# frozen_string_literal: true

# Unit tests for DnsRecordCheckWorker's dns_verified computation (issue #4047).
#
# Regression: dns_verified used to be `records.all? { value_matches }`, so an
# EMPTY record set (domain not provisioned, or every record optional) read as
# verified — [].all? is vacuously true. It is now `records.any? && all_matched`:
# absence of evidence is not verification.
#
# Seams: the worker is instantiated for real (Sneakers::Queue does not connect
# until subscribe), but everything stateful is stubbed — trace context yields
# straight through, the idempotency claim is granted, MailerConfig lookup and
# the sender strategy return doubles, and the logger is a null object. ack! /
# reject! are Sneakers methods that just return symbols; asserting on the
# return value pins the outcome.

require 'spec_helper'
require 'onetime/jobs/workers/dns_record_check_worker'

RSpec.describe Onetime::Jobs::Workers::DnsRecordCheckWorker do
  let(:worker) { described_class.new }

  let(:delivery_info) do
    double('DeliveryInfo', delivery_tag: 1, routing_key: described_class::QUEUE_NAME, redelivered?: false)
  end
  let(:amqp_metadata) { double('MessageProperties', message_id: 'msg-4047', headers: nil) }
  let(:msg) { { domain_id: 'domain-abc', requested_at: '2026-08-08T00:00:00Z' }.to_json }

  let(:dns_check_results_key) { double('dns_check_results', :value= => nil) }
  let(:mailer_config) do
    double(
      'MailerConfig',
      dns_check_status: nil,
      :dns_check_status= => nil,
      :dns_verified= => nil,
      :dns_check_completed_at= => nil,
      :updated= => nil,
      save_fields: true,
      refresh!: true,
      jobs_completed?: false,
      provider_check_status: 'pending',
      effective_provider: 'lettermint',
      dns_check_results: dns_check_results_key,
    )
  end
  let(:strategy) { double('SenderStrategy', check_dns_records: { records: dns_records, checked_at: Time.now }) }

  before do
    allow(worker).to receive(:logger).and_return(double('logger').as_null_object)
    allow(worker).to receive(:with_trace_context).and_yield
    allow(worker).to receive(:claim_for_processing).and_return(true)
    allow(Onetime::CustomDomain::MailerConfig).to receive(:find_by_domain_id)
      .with('domain-abc').and_return(mailer_config)
    allow(Onetime::Mail::SenderStrategies).to receive(:for_provider)
      .with('lettermint').and_return(strategy)
  end

  def work
    worker.work_with_params(msg, delivery_info, amqp_metadata)
  end

  describe 'dns_verified computation' do
    context 'with an empty record set (the #4047 vacuous-truth regression)' do
      let(:dns_records) { [] }

      it 'sets dns_verified false — absence of evidence is not verification' do
        expect(work).to eq(:ack)
        expect(mailer_config).to have_received(:dns_verified=).with(false)
      end

      it 'still persists the (empty) fact-finding results and completion' do
        work
        expect(dns_check_results_key).to have_received(:value=).with([])
        expect(mailer_config).to have_received(:save_fields)
          .with(:dns_check_status, :dns_verified, :dns_check_completed_at, :updated)
      end
    end

    context 'when every record matched' do
      let(:dns_records) do
        [
          { 'type' => 'CNAME', 'name' => 'a.example.com', 'value_matches' => true },
          { 'type' => 'TXT', 'name' => 'b.example.com', 'value_matches' => true },
        ]
      end

      it 'sets dns_verified true' do
        expect(work).to eq(:ack)
        expect(mailer_config).to have_received(:dns_verified=).with(true)
      end
    end

    context 'when records use symbol keys' do
      let(:dns_records) { [{ type: 'TXT', name: 'a.example.com', value_matches: true }] }

      it 'still recognizes the match' do
        work
        expect(mailer_config).to have_received(:dns_verified=).with(true)
      end
    end

    context 'when one record does not match' do
      let(:dns_records) do
        [
          { 'type' => 'CNAME', 'name' => 'a.example.com', 'value_matches' => true },
          { 'type' => 'TXT', 'name' => 'b.example.com', 'value_matches' => false, 'error' => 'ambiguous_record_set' },
        ]
      end

      it 'sets dns_verified false' do
        expect(work).to eq(:ack)
        expect(mailer_config).to have_received(:dns_verified=).with(false)
      end
    end

    context 'when the strategy result has no records key' do
      let(:strategy) { double('SenderStrategy', check_dns_records: { checked_at: Time.now }) }
      let(:dns_records) { nil }

      it 'treats nil records as empty and sets dns_verified false' do
        work
        expect(mailer_config).to have_received(:dns_verified=).with(false)
      end
    end
  end
end

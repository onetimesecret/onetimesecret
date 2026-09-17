# frozen_string_literal: true

require_relative 'cli_spec_helper'

RSpec.describe Onetime::CLI::CustomersPurgeCommand do
  let(:command) { described_class.new }
  let(:membership_snapshot) { Auth::Operations::Customers::MembershipSnapshot.new({}) }

  before do
    allow(Auth::Operations::Customers::MembershipSnapshot).to receive(:capture).and_return(membership_snapshot)
  end

  def capture_stdout
    original = $stdout
    $stdout  = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  it 'routes local candidates through the receipt-backed bulk purge lifecycle' do
    customer = instance_double(Onetime::Customer)
    result   = instance_double(Auth::Operations::Customers::Purge::Result, status: :success)
    operation = instance_double(Auth::Operations::Customers::Purge, call: result)
    context = instance_double(Onetime::Operations::BulkAuditContext)
    cutoff = Time.utc(2024, 1, 2)

    # The registry snapshot is captured once per run and shared by every
    # candidate; the per-account untracked-session keyspace walk is declined.
    expect(Auth::Operations::Customers::Purge).to receive(:new).with(
      customer: customer,
      actor: Onetime::CLI::Customers::Shared::CLI_ACTOR,
      reason: 'bulk inactivity purge before 2024-01-02',
      bulk_audit_context: context,
      membership_snapshot: membership_snapshot,
      sweep_untracked_sessions: false,
    ).and_return(operation)

    expect(command.send(:purge_customer, customer, cutoff, context, membership_snapshot)).to equal(result)
  end

  it 'captures the membership registry once per run, after the start receipt, and shares it' do
    customer     = double('customer')
    cache_redis  = double('cache redis', zcard: 2, zrem: 1)
    source_redis = double('source redis')
    result       = instance_double(Auth::Operations::Customers::Purge::Result, status: :success)
    records      = {
      'cust_1' => { _model: customer, email: 'a@example.com' },
      'cust_2' => { _model: customer, email: 'b@example.com' },
    }

    command.instance_variable_set(:@using_remote, false)
    allow(command).to receive(:batch_load_customer_records).and_return(records)
    allow(Onetime::ColonelAuditEvent).to receive(:record).and_return('id' => 'receipt')
    allow(command).to receive(:purge_customer).and_return(result)

    capture_stdout do
      command.send(:execute_purge, source_redis, cache_redis, %w[cust_1 cust_2], Time.utc(2024, 1, 2))
    end

    expect(Auth::Operations::Customers::MembershipSnapshot).to have_received(:capture).once
    expect(command).to have_received(:purge_customer)
      .with(customer, kind_of(Time), kind_of(Onetime::Operations::BulkAuditContext), membership_snapshot).twice
  end

  it 'records bounded start and completion receipts instead of one event per candidate' do
    candidate_count = Onetime::ColonelAuditEvent::MAX_EVENTS + 1
    candidates      = Array.new(candidate_count) { |index| "cust_#{index}" }
    cache_redis     = double('cache redis', zcard: candidate_count, zrem: 1)
    source_redis    = double('source redis')
    result          = instance_double(Auth::Operations::Customers::Purge::Result, status: :success)

    command.instance_variable_set(:@using_remote, false)
    allow(command).to receive(:batch_load_customer_records) do |_source, batch|
      batch.to_h { |objid| [objid, { _model: double('customer'), email: 'masked@example.com' }] }
    end
    allow(command).to receive(:purge_customer).and_return(result)
    allow(Onetime::ColonelAuditEvent).to receive(:record)
      .and_return({ 'id' => 'start-receipt' }, { 'id' => 'completion-receipt' })

    capture_stdout do
      command.send(:execute_purge, source_redis, cache_redis, candidates, Time.utc(2024, 1, 2))
    end

    expect(command).to have_received(:purge_customer).exactly(candidate_count).times
    expect(Onetime::ColonelAuditEvent).to have_received(:record).twice
    expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
      actor: Onetime::CLI::Customers::Shared::CLI_ACTOR,
      verb: 'customer.purge.bulk',
      target: 'inactive-customers',
      result: :started,
      detail: hash_including(candidates: candidate_count, batch_size: 50),
      fail_closed: true,
    )
    expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
      actor: Onetime::CLI::Customers::Shared::CLI_ACTOR,
      verb: 'customer.purge.bulk',
      target: 'inactive-customers',
      result: :success,
      detail: hash_including(
        candidates: candidate_count,
        destroyed: candidate_count,
        errors: 0,
        start_receipt_id: 'start-receipt',
      ),
      fail_closed: true,
    )
  end

  it 'does not mutate candidates when the bulk start receipt cannot be recorded' do
    cache_redis = double('cache redis', zcard: 1)
    source_redis = double('source redis')
    failure = Onetime::AuditWriteFailure.new(
      verb: 'customer.purge.bulk',
      target: 'inactive-customers',
    )

    command.instance_variable_set(:@using_remote, false)
    allow(Onetime::ColonelAuditEvent).to receive(:record).and_raise(failure)
    expect(command).not_to receive(:batch_load_customer_records)
    expect(command).not_to receive(:purge_customer)

    expect do
      capture_stdout do
        command.send(:execute_purge, source_redis, cache_redis, ['cust_1'], Time.utc(2024, 1, 2))
      end
    end.to raise_error(Onetime::AuditWriteFailure)
  end

  it 'records the start receipt before the first candidate mutation' do
    customer = double('customer')
    cache_redis = double('cache redis', zcard: 1, zrem: 1)
    source_redis = double('source redis')
    result = instance_double(Auth::Operations::Customers::Purge::Result, status: :success)

    command.instance_variable_set(:@using_remote, false)
    allow(command).to receive(:batch_load_customer_records)
      .and_return('cust_1' => { _model: customer, email: 'masked@example.com' })
    expect(Onetime::ColonelAuditEvent).to receive(:record).with(
      hash_including(result: :started)
    ).ordered.and_return('id' => 'start-receipt')
    expect(command).to receive(:purge_customer).ordered.and_return(result)
    expect(Onetime::ColonelAuditEvent).to receive(:record).with(
      hash_including(result: :success)
    ).ordered.and_return('id' => 'completion-receipt')

    capture_stdout do
      command.send(:execute_purge, source_redis, cache_redis, ['cust_1'], Time.utc(2024, 1, 2))
    end
  end

  it 'leaves the start receipt when execution terminates mid-loop' do
    customer = double('customer')
    cache_redis = double('cache redis', zcard: 1)
    source_redis = double('source redis')

    command.instance_variable_set(:@using_remote, false)
    allow(command).to receive(:batch_load_customer_records)
      .and_return('cust_1' => { _model: customer, email: 'masked@example.com' })
    allow(command).to receive(:purge_customer).and_raise(Interrupt)
    allow(Onetime::ColonelAuditEvent).to receive(:record).and_return('id' => 'start-receipt')

    expect do
      capture_stdout do
        command.send(:execute_purge, source_redis, cache_redis, ['cust_1'], Time.utc(2024, 1, 2))
      end
    end.to raise_error(Interrupt)

    expect(Onetime::ColonelAuditEvent).to have_received(:record).once.with(
      hash_including(result: :started)
    )
  end

  it 'refuses destructive remote mode instead of deleting raw keys' do
    command.instance_variable_set(:@using_remote, true)
    original = $stdout
    output   = StringIO.new
    $stdout  = output

    expect do
      command.send(:execute_purge, double('source redis'), double('cache redis'), ['cust_target'], Time.now)
    end.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }

    expect(output.string).to include('--purge with --redis-url is disabled')
    expect(output.string).to include('safe lifecycle')
  ensure
    $stdout = original
  end
end

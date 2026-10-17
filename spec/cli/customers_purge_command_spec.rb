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
    result   = instance_double(Auth::Operations::Customers::Purge::Result, status: :success, actions: [])
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
    result       = instance_double(Auth::Operations::Customers::Purge::Result, status: :success, actions: [])
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
    result          = instance_double(Auth::Operations::Customers::Purge::Result, status: :success, actions: [])

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
        stale_participations_removed: 0,
        errors: 0,
        start_receipt_id: 'start-receipt',
      ),
      fail_closed: true,
    )
  end

  [:success, :partial].each do |status|
    it "aggregates completed stale-reference cleanup in the #{status} completion receipt" do
      cache_redis  = double('cache redis', zcard: 2, zrem: 1)
      source_redis = double('source redis')
      actions = [
        { type: :remove_stale_participation, status: :success, reference: 'organization:gone:members' },
        { type: :remove_stale_participation, status: :success, reference: 'organization:other:members' },
        { type: :remove_stale_participation, status: :refused },
        { type: :remove_membership, status: :success },
      ]
      result = instance_double(
        Auth::Operations::Customers::Purge::Result,
        status: status, actions: actions, stage: :teardown,
        completed_stages: [:remove_stale_participation], blockers: [],
      )
      unchanged = instance_double(Auth::Operations::Customers::Purge::Result, status: :success, actions: [])
      records = %w[cust_1 cust_2].to_h do |objid|
        [objid, { _model: double('customer'), email: 'masked@example.com' }]
      end

      command.instance_variable_set(:@using_remote, false)
      allow(command).to receive(:batch_load_customer_records).and_return(records)
      allow(command).to receive(:purge_customer).and_return(result, unchanged)
      allow(Onetime::ColonelAuditEvent).to receive(:record)
        .and_return({ 'id' => 'start-receipt' }, { 'id' => 'completion-receipt' })

      output = capture_stdout do
        run = -> { command.send(:execute_purge, source_redis, cache_redis, records.keys, Time.utc(2024, 1, 2)) }
        if status == :partial
          expect(&run).to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
        else
          run.call
        end
      end

      expect(output).to include('Stale references removed: 2')
      expect(Onetime::ColonelAuditEvent).to have_received(:record).twice
      expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
        hash_including(
          result: status == :partial ? :failure : :success,
          detail: {
            cutoff: '2024-01-02', candidates: 2,
            destroyed: status == :partial ? 1 : 2,
            stale_participations_removed: 2,
            billing_protected: 0, refused: 0,
            partial: status == :partial ? 1 : 0,
            not_found: 0, skipped: 0, errors: status == :partial ? 1 : 0,
            start_receipt_id: 'start-receipt',
          },
        ),
      )
    end
  end

  [:during_purge, :after_result].each do |failure_point|
    it "counts completed cleanup once when an exception occurs #{failure_point}, without reusing the previous operation" do
      cache_redis  = double('cache redis', zcard: 2, zrem: 1)
      source_redis = double('source redis')
      customer = double('customer')
      next_customer = double('next customer')
      actions = [
        { type: :remove_stale_participation, status: :success, reference: 'organization:gone:members' },
        { type: :remove_stale_participation, status: :refused },
        { type: :remove_membership, status: :success },
      ]
      result = instance_double(Auth::Operations::Customers::Purge::Result, status: :success, actions: actions)
      operation = instance_double(
        Auth::Operations::Customers::Purge,
        outcome_context: { stage: :account_teardown, actions: actions },
      )
      if failure_point == :during_purge
        allow(operation).to receive(:call).and_raise(StandardError, 'close_auth failed')
      else
        allow(operation).to receive(:call).and_return(result)
        allow(OT).to receive(:info).with('[purge] Destroyed cust_1 masked@example.com')
          .and_raise(StandardError, 'logging failed')
      end
      records = {
        'cust_1' => { _model: customer, email: 'masked@example.com' },
        'cust_2' => { _model: next_customer, email: 'next@example.com' },
      }

      command.instance_variable_set(:@using_remote, false)
      allow(command).to receive(:batch_load_customer_records).and_return(records)
      allow(Auth::Operations::Customers::Purge).to receive(:new)
        .with(hash_including(customer: customer)).and_return(operation)
      allow(Auth::Operations::Customers::Purge).to receive(:new)
        .with(hash_including(customer: next_customer)).and_raise(StandardError, 'initialization failed')
      allow(Onetime::ColonelAuditEvent).to receive(:record)
        .and_return({ 'id' => 'start-receipt' }, { 'id' => 'completion-receipt' })

      output = capture_stdout do
        expect do
          command.send(:execute_purge, source_redis, cache_redis, records.keys, Time.utc(2024, 1, 2))
        end.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end

      expect(output).to include('Stale references removed: 1')
      expect(operation).to have_received(:call).once
      if failure_point == :during_purge
        expect(operation).to have_received(:outcome_context).once
      else
        expect(operation).not_to have_received(:outcome_context)
      end
      expect(Onetime::ColonelAuditEvent).to have_received(:record).twice
      expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
        hash_including(
          result: :failure,
          detail: {
            cutoff: '2024-01-02', candidates: 2,
            destroyed: failure_point == :after_result ? 1 : 0,
            stale_participations_removed: 1,
            billing_protected: 0, refused: 0, partial: 0,
            not_found: 0, skipped: 0, errors: 2,
            start_receipt_id: 'start-receipt',
          },
        ),
      )
    end
  end

  # A bulk refusal writes no operator-trail event of its own (the completion
  # receipt carries only the refused count), so the log line is the only place
  # a candidate's blocker codes persist. It names codes, never the email.
  it 'logs the blocker codes of refused and partial candidates without the email' do
    customer     = double('customer')
    cache_redis  = double('cache redis', zcard: 2, zrem: 1)
    source_redis = double('source redis')
    refused = instance_double(
      Auth::Operations::Customers::Purge::Result,
      status: :refused, stage: :preflight, completed_stages: [], actions: [],
      blockers: [{ code: :has_domains, org_id: 'on_1' }, { code: :has_domains, org_id: 'on_2' }],
    )
    partial = instance_double(
      Auth::Operations::Customers::Purge::Result,
      status: :partial, stage: :teardown, completed_stages: [:cleanup], actions: [],
      blockers: [{ code: :references_remain }],
    )
    records = {
      'cust_1' => { _model: customer, email: 'refused@example.com' },
      'cust_2' => { _model: customer, email: 'partial@example.com' },
    }

    command.instance_variable_set(:@using_remote, false)
    allow(command).to receive(:batch_load_customer_records).and_return(records)
    allow(Onetime::ColonelAuditEvent).to receive(:record).and_return('id' => 'receipt')
    allow(command).to receive(:purge_customer).and_return(refused, partial)
    logged = []
    allow(OT).to receive(:info) { |*args| logged << args.map(&:to_s).join(' ') }

    expect do
      capture_stdout do
        command.send(:execute_purge, source_redis, cache_redis, %w[cust_1 cust_2], Time.utc(2024, 1, 2))
      end
    end.to raise_error(SystemExit)

    expect(OT).to have_received(:info).with('[purge] Refused cust_1 blockers=has_domains')
    expect(OT).to have_received(:info).with('[purge] Partial cust_2 stage=teardown blockers=references_remain')
    # Substring, not a regex: the assertion is that the address never appears
    # anywhere in a log line, which is exactly the unanchored match CodeQL
    # objects to when a pattern like this is used for URL matching.
    expect(logged.select { |message| message.include?('example.com') }).to be_empty
    expect(Onetime::ColonelAuditEvent).to have_received(:record).with(
      hash_including(result: :failure, detail: hash_including(refused: 1, partial: 1, errors: 2)),
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
    result = instance_double(Auth::Operations::Customers::Purge::Result, status: :success, actions: [])

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

  # Remote mode (--redis-url) reads customer:{objid}:participations with a raw
  # client. Familia writes each collection key into that set JSON-quoted, so a
  # raw reader has to decode an entry before matching its prefix.
  describe 'org-level billing check in remote mode (real datastore)', :datastore do
    let(:suffix) { "#{Familia.now.to_i}#{SecureRandom.hex(4)}" }

    before do
      @customers = []
      @orgs      = []
    end

    after do
      @orgs.each do |org|
        org.destroy! if org.exists?
      rescue StandardError => ex
        warn "[purge spec] org cleanup failed: #{ex.class}: #{ex.message}"
      end
      @customers.each do |cust|
        cust.destroy! if cust.exists?
      rescue StandardError => ex
        warn "[purge spec] customer cleanup failed: #{ex.class}: #{ex.message}"
      end
    end

    def create_member_of_org(label)
      owner = Onetime::Customer.create!(email: "purge_billing_#{label}_#{suffix}@onetimesecret.com")
      @customers << owner
      org = Onetime::Organization.create!("Purge Billing #{label} #{suffix}", owner)
      @orgs << org
      [owner, org]
    end

    it 'finds Stripe billing on an organization the customer belongs to' do
      owner, org             = create_member_of_org('billed')
      org.stripe_customer_id = "cus_purge#{suffix}"
      org.save

      expect(command.send(:org_billing_raw?, Onetime::Customer.dbclient, owner.objid)).to be(true)
    end

    it 'finds no billing when the organization has none' do
      owner, _org = create_member_of_org('unbilled')

      expect(command.send(:org_billing_raw?, Onetime::Customer.dbclient, owner.objid)).to be(false)
    end
  end
end

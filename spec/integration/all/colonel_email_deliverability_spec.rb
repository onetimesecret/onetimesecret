# spec/integration/all/colonel_email_deliverability_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

# Load the ColonelAPI application and its dependencies
# (apps/api is in the load path from spec_helper).
require 'colonel/application'

# Integration tests for the email deliverability colonel endpoints against real
# Redis (port 2121; type: :integration flushes after each example):
#
#   1. Ingest — IngestEmailDeliverabilityEvents (POST /api/colonel/email/
#      deliverability/events): batch feedback ingestion, suppression writes,
#      per-record rejection, and the one-audit-event-per-batch rule.
#   2. Summary — GetEmailDeliverability: the counters (suppressed total,
#      recent bounces/complaints, sends skipped). Read-only (CONTRACT 4).
#   3. Suppressions — ListEmailSuppressions (pagination + exact-address
#      search) and RemoveEmailSuppression (guarded delete, audited, 404 on
#      unknown address).
#   4. Events — ListEmailDeliverabilityEvents: newest-first feed pagination.
RSpec.describe 'Colonel email deliverability endpoints', type: :integration do
  # Build the StrategyResult double Logic::Base expects (mirrors
  # colonel_observability_spec.rb). The colonel is a REAL verified customer
  # so verify_one_of_roles!(colonel: true) exercises the actual policy.
  def strategy_result_for(user)
    double(
      'StrategyResult',
      session: {},
      user: user,
      metadata: { ip: '127.0.0.1' },
      auth_method: 'sessionauth',
    )
  end

  def create_customer(email:, role: 'customer', verified: 'true')
    cust          = Onetime::Customer.create!(email: email)
    cust.role     = role
    cust.verified = verified
    cust.save
    cust
  end

  let(:colonel) do
    create_customer(email: "colonel-#{SecureRandom.hex(4)}@example.com", role: 'colonel')
  end

  def clear_deliverability
    Onetime::EmailSuppression.entries.clear
    Onetime::EmailSuppression.index.clear
    Onetime::EmailSuppression.events.clear
    Onetime::EmailSuppression.sends_skipped.clear
  end

  before do
    Onetime::AdminAuditEvent.events.clear
    clear_deliverability
  end

  def run_logic(klass, params = {}, actor: colonel)
    logic = klass.new(strategy_result_for(actor), params)
    logic.raise_concerns
    logic.process
  end

  # ---------------------------------------------------------------------------
  # 1. Ingest (IngestEmailDeliverabilityEvents)
  # ---------------------------------------------------------------------------
  describe 'IngestEmailDeliverabilityEvents' do
    def ingest(events, source: nil)
      params = { 'events' => events }
      params['source'] = source if source
      run_logic(ColonelAPI::Logic::Colonel::IngestEmailDeliverabilityEvents, params)
    end

    it 'ingests bounces/complaints into the feed AND suppresses the addresses' do
      data = ingest(
        [
          { 'email' => 'Bounce@Example.com', 'kind' => 'bounce', 'reason' => '550 user unknown' },
          { 'email' => 'gripe@example.com', 'kind' => 'complaint' },
        ],
        source: 'ses',
      )

      expect(data[:record]).to eq(accepted: 2, rejected: 0)
      expect(Onetime::EmailSuppression.suppressed?('bounce@example.com')).to be(true)
      expect(Onetime::EmailSuppression.lookup('gripe@example.com')['reason']).to eq('complaint')
      kinds = Onetime::EmailSuppression.recent_events(5).map { |e| e['kind'] }
      expect(kinds).to contain_exactly('bounce', 'complaint')
      expect(Onetime::EmailSuppression.recent_events(5).map { |e| e['source'] }).to all(eq('ses'))
    end

    it "imports 'suppression' records onto the list without a feed event" do
      data = ingest([{ 'email' => 'import@example.com', 'kind' => 'suppression' }])

      expect(data[:record][:accepted]).to eq(1)
      expect(Onetime::EmailSuppression.lookup('import@example.com')['reason']).to eq('manual')
      expect(Onetime::EmailSuppression.event_count).to eq(0)
    end

    it 'rejects malformed records without failing the batch, describing why' do
      data = ingest(
        [
          { 'email' => 'ok@example.com', 'kind' => 'bounce' },
          { 'email' => 'not-an-email', 'kind' => 'bounce' },
          { 'email' => 'x@example.com', 'kind' => 'exploded' },
        ],
      )

      expect(data[:record]).to eq(accepted: 1, rejected: 2)
      expect(data[:details][:errors]).to contain_exactly(
        'record 2: missing or invalid email',
        "record 3: unknown kind 'exploded'",
      )
      expect(Onetime::EmailSuppression.count).to eq(1)
    end

    it 'records EXACTLY ONE audit event per accepting batch (CONTRACT 4)' do
      ingest(
        [
          { 'email' => 'a@example.com', 'kind' => 'bounce' },
          { 'email' => 'b@example.com', 'kind' => 'complaint' },
        ],
        source: 'sendgrid',
      )

      expect(Onetime::AdminAuditEvent.count).to eq(1)
      event = Onetime::AdminAuditEvent.recent(1).first
      expect(event['verb']).to eq('email.deliverability_ingest')
      expect(event['actor']).to eq(colonel.extid)
      expect(event['detail']).to include('accepted' => 2, 'rejected' => 0, 'source' => 'sendgrid')
    end

    it 'records NO audit event when nothing was accepted (no mutation, no audit)' do
      ingest([{ 'email' => 'nope', 'kind' => 'bounce' }])

      expect(Onetime::AdminAuditEvent.count).to eq(0)
    end

    it 'rejects a missing/empty events array as a form error' do
      logic = ColonelAPI::Logic::Colonel::IngestEmailDeliverabilityEvents.new(
        strategy_result_for(colonel), {},
      )
      expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /non-empty array/)
    end

    it 'rejects an oversized batch as a form error' do
      too_many = Array.new(Onetime::Operations::Email::IngestFeedback::MAX_BATCH + 1) do |i|
        { 'email' => "u#{i}@example.com", 'kind' => 'bounce' }
      end
      logic = ColonelAPI::Logic::Colonel::IngestEmailDeliverabilityEvents.new(
        strategy_result_for(colonel), { 'events' => too_many },
      )
      expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /batch too large/)
    end

    it 'rejects non-colonel actors (defense-in-depth below the router role gate)' do
      staff = create_customer(email: "staff-#{SecureRandom.hex(4)}@example.com", role: 'staff')
      logic = ColonelAPI::Logic::Colonel::IngestEmailDeliverabilityEvents.new(
        strategy_result_for(staff), { 'events' => [{ 'email' => 'a@example.com', 'kind' => 'bounce' }] },
      )
      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Summary (GetEmailDeliverability)
  # ---------------------------------------------------------------------------
  describe 'GetEmailDeliverability' do
    def summary
      run_logic(ColonelAPI::Logic::Colonel::GetEmailDeliverability)
    end

    it 'returns zeroed counts on a clean slate' do
      data = summary

      expect(data[:details][:counts]).to eq(
        suppressed_total: 0, recent_bounces: 0, recent_complaints: 0, sends_skipped: 0,
      )
      expect(data[:details][:window_days]).to eq(7)
    end

    it 'reflects suppressions, recent events, and counted skips' do
      Onetime::EmailSuppression.suppress!(address: 'a@example.com', reason: 'bounce')
      Onetime::EmailSuppression.record_event(address: 'a@example.com', kind: 'bounce')
      Onetime::EmailSuppression.record_event(address: 'b@example.com', kind: 'complaint')
      Onetime::EmailSuppression.skip_send?('a@example.com')

      counts = summary[:details][:counts]

      expect(counts).to eq(
        suppressed_total: 1, recent_bounces: 1, recent_complaints: 1, sends_skipped: 1,
      )
    end

    it 'reading the summary writes NO audit event (CONTRACT 4)' do
      summary
      expect(Onetime::AdminAuditEvent.count).to eq(0)
    end
  end

  # ---------------------------------------------------------------------------
  # 3. Suppression list + removal
  # ---------------------------------------------------------------------------
  describe 'ListEmailSuppressions' do
    def list(params = {})
      run_logic(ColonelAPI::Logic::Colonel::ListEmailSuppressions, params)
    end

    it 'pages newest-first with the pagination envelope' do
      3.times { |i| Onetime::EmailSuppression.suppress!(address: "s#{i}@example.com", reason: 'manual') }

      data = list('page' => 1, 'per_page' => 2)

      expect(data[:details][:suppressions].map { |s| s[:address] })
        .to eq(%w[s2@example.com s1@example.com])
      expect(data[:details][:pagination]).to include(
        page: 1, per_page: 2, total_count: 3, total_pages: 2,
      )
      page2 = list('page' => 2, 'per_page' => 2)
      expect(page2[:details][:suppressions].map { |s| s[:address] }).to eq(%w[s0@example.com])
    end

    it 'searches by EXACT address (single keyed lookup, normalized)' do
      Onetime::EmailSuppression.suppress!(address: 'hit@example.com', reason: 'bounce', source: 'ses')
      Onetime::EmailSuppression.suppress!(address: 'other@example.com', reason: 'manual')

      data = list('search' => 'HIT@example.com')

      expect(data[:details][:suppressions].length).to eq(1)
      expect(data[:details][:suppressions].first).to include(
        address: 'hit@example.com', reason: 'bounce', source: 'ses',
      )
      expect(data[:details][:pagination]).to include(total_count: 1, search: 'HIT@example.com')

      miss = list('search' => 'hit@example.co')
      expect(miss[:details][:suppressions]).to eq([])
      expect(miss[:details][:pagination][:total_count]).to eq(0)
    end
  end

  describe 'RemoveEmailSuppression' do
    it 'removes the entry and records one audit event with the lifted reason' do
      Onetime::EmailSuppression.suppress!(address: 'gone@example.com', reason: 'complaint', source: 'ses')

      data = run_logic(
        ColonelAPI::Logic::Colonel::RemoveEmailSuppression, { 'address' => 'Gone@Example.com' },
      )

      expect(data[:record]).to eq(address: 'gone@example.com', removed: true)
      expect(Onetime::EmailSuppression.suppressed?('gone@example.com')).to be(false)

      expect(Onetime::AdminAuditEvent.count).to eq(1)
      event = Onetime::AdminAuditEvent.recent(1).first
      expect(event).to include(
        'verb' => 'email.suppression_remove',
        'actor' => colonel.extid,
        'target' => 'gone@example.com',
        'result' => 'success',
      )
      expect(event['detail']).to include('reason' => 'complaint', 'source' => 'ses')
    end

    it '404s for an address that is not suppressed and audits nothing' do
      logic = ColonelAPI::Logic::Colonel::RemoveEmailSuppression.new(
        strategy_result_for(colonel), { 'address' => 'never@example.com' },
      )
      expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound)
      expect(Onetime::AdminAuditEvent.count).to eq(0)
    end

    it 'rejects non-colonel actors' do
      staff = create_customer(email: "staff-#{SecureRandom.hex(4)}@example.com", role: 'staff')
      Onetime::EmailSuppression.suppress!(address: 'a@example.com', reason: 'manual')

      logic = ColonelAPI::Logic::Colonel::RemoveEmailSuppression.new(
        strategy_result_for(staff), { 'address' => 'a@example.com' },
      )
      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
    end
  end

  # ---------------------------------------------------------------------------
  # 4. Event feed (ListEmailDeliverabilityEvents)
  # ---------------------------------------------------------------------------
  describe 'ListEmailDeliverabilityEvents' do
    def list_events(params = {})
      run_logic(ColonelAPI::Logic::Colonel::ListEmailDeliverabilityEvents, params)
    end

    it 'returns events newest-first with explicit fields and pagination' do
      Onetime::EmailSuppression.record_event(
        address: 'a@example.com', kind: 'bounce', reason: '550', source: 'smtp-sync',
      )
      Onetime::EmailSuppression.record_event(address: 'b@example.com', kind: 'complaint', source: 'ses')

      data = list_events

      events = data[:details][:events]
      expect(events.map { |e| e[:kind] }).to eq(%w[complaint bounce])
      expect(events.last.keys).to contain_exactly(:id, :address, :kind, :reason, :source, :created)
      expect(events.last).to include(address: 'a@example.com', reason: '550', source: 'smtp-sync')
      expect(events.last[:created]).to be_a(Float)
      expect(data[:details][:pagination]).to include(total_count: 2, total_pages: 1)
    end

    it 'paginates the feed (page 2 carries the older slice)' do
      3.times { |i| Onetime::EmailSuppression.record_event(address: "e#{i}@example.com", kind: 'bounce') }

      page2 = list_events('page' => 2, 'per_page' => 2)

      expect(page2[:details][:events].map { |e| e[:address] }).to eq(%w[e0@example.com])
      expect(page2[:details][:pagination]).to include(total_count: 3, total_pages: 2)
    end

    it 'reading the feed writes NO audit event (CONTRACT 4)' do
      list_events
      expect(Onetime::AdminAuditEvent.count).to eq(0)
    end
  end
end

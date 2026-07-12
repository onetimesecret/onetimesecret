# spec/integration/all/colonel_observability_spec.rb
#
# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'

# Load the ColonelAPI application and its dependencies
# (apps/api is in the load path from spec_helper).
require 'colonel/application'

# Integration tests for the observability colonel endpoints against real Redis
# (port 2121; type: :integration flushes after each example):
#
#   1. Audit log reader — ListAuditEvents (GET /api/colonel/audit): newest-first
#      pagination, actor/verb filters, and the CONTRACT 4 invariant that reading
#      the log never writes an audit event.
#   2. Trends — GetTrends (GET /api/colonel/trends): 30-day zero-filled series
#      fed by the DailyMetric chokepoint counters, also read-only.
RSpec.describe 'Colonel observability endpoints', type: :integration do
  # Build the StrategyResult double Logic::Base expects (mirrors
  # colonel_customer_support_spec.rb). The colonel is a REAL verified customer
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

  before { Onetime::AdminAuditEvent.events.clear }

  def record_event(actor: 'ur_colonel1', verb: 'customer.set_role', target: 'ur_target', result: :success, detail: nil)
    Onetime::AdminAuditEvent.record(actor: actor, verb: verb, target: target, result: result, detail: detail)
  end

  # ---------------------------------------------------------------------------
  # 1. Audit log reader (ListAuditEvents)
  # ---------------------------------------------------------------------------
  describe 'ListAuditEvents' do
    def list(params = {})
      logic = ColonelAPI::Logic::Colonel::ListAuditEvents.new(
        strategy_result_for(colonel), params,
      )
      logic.raise_concerns
      logic.process
    end

    it 'returns events newest-first with the pagination envelope' do
      record_event(verb: 'customer.set_role')
      record_event(verb: 'session.delete')
      record_event(verb: 'banner.set')

      data = list

      verbs = data[:details][:events].map { |e| e[:verb] }
      expect(verbs).to eq(%w[banner.set session.delete customer.set_role])
      expect(data[:details][:pagination]).to include(
        page: 1, per_page: 50, total_count: 3, total_pages: 1,
      )
    end

    it 'emits the explicit event fields (timestamp/actor/action/target/detail)' do
      record_event(
        actor: 'ur_actor1', verb: 'customer.purge', target: 'ur_victim',
        detail: { 'reason' => 'gdpr' },
      )

      event = list[:details][:events].first

      expect(event.keys).to contain_exactly(:id, :actor, :verb, :target, :result, :detail, :created)
      expect(event).to include(
        actor: 'ur_actor1', verb: 'customer.purge', target: 'ur_victim', result: 'success',
        detail: { 'reason' => 'gdpr' },
      )
      expect(event[:created]).to be_a(Float)
    end

    it 'paginates newest-first: page 2 carries the older slice' do
      5.times { |i| record_event(verb: "v#{i}") } # v4 is the newest

      page1 = list('page' => 1, 'per_page' => 2)
      page2 = list('page' => 2, 'per_page' => 2)
      page3 = list('page' => 3, 'per_page' => 2)

      expect(page1[:details][:events].map { |e| e[:verb] }).to eq(%w[v4 v3])
      expect(page2[:details][:events].map { |e| e[:verb] }).to eq(%w[v2 v1])
      expect(page3[:details][:events].map { |e| e[:verb] }).to eq(%w[v0])
      expect(page1[:details][:pagination]).to include(total_count: 5, total_pages: 3)
    end

    it 'returns an empty page (not an error) past the last page' do
      record_event

      data = list('page' => 9, 'per_page' => 50)

      expect(data[:details][:events]).to eq([])
      expect(data[:details][:pagination][:total_count]).to eq(1)
    end

    it 'filters by actor with case-insensitive substring matching' do
      record_event(actor: 'ur_alice123', verb: 'v.alice')
      record_event(actor: 'ur_bob456', verb: 'v.bob')

      data = list('actor' => 'ALICE')

      expect(data[:details][:events].map { |e| e[:verb] }).to eq(%w[v.alice])
      expect(data[:details][:pagination]).to include(total_count: 1, actor: 'ALICE')
    end

    it 'filters by exact action verb' do
      record_event(verb: 'customer.set_role')
      record_event(verb: 'customer.purge')

      data = list('verb' => 'customer.purge')

      expect(data[:details][:events].map { |e| e[:verb] }).to eq(%w[customer.purge])
    end

    it 'filters by action category prefix (customer matches customer.*)' do
      record_event(verb: 'customer.set_role')
      record_event(verb: 'customer.purge')
      record_event(verb: 'session.delete')

      data = list('verb' => 'customer')

      expect(data[:details][:events].map { |e| e[:verb] })
        .to contain_exactly('customer.set_role', 'customer.purge')
      expect(data[:details][:pagination][:verb]).to eq('customer')
    end

    it 'paginates filtered results with a filtered total_count' do
      3.times { |i| record_event(verb: "customer.v#{i}") }
      record_event(verb: 'session.delete')

      data = list('verb' => 'customer', 'page' => 2, 'per_page' => 2)

      expect(data[:details][:events].length).to eq(1)
      expect(data[:details][:pagination]).to include(total_count: 3, total_pages: 2)
    end

    it 'reading the log writes NO audit event (CONTRACT 4)' do
      record_event
      before_count = Onetime::AdminAuditEvent.count

      list
      list('actor' => 'someone', 'verb' => 'customer')

      expect(Onetime::AdminAuditEvent.count).to eq(before_count)
    end

    it 'rejects non-colonel actors (defense-in-depth below the router role gate)' do
      staff = create_customer(email: "staff-#{SecureRandom.hex(4)}@example.com", role: 'staff')

      logic = ColonelAPI::Logic::Colonel::ListAuditEvents.new(strategy_result_for(staff), {})
      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
    end
  end

  # ---------------------------------------------------------------------------
  # 2. Trends (GetTrends)
  # ---------------------------------------------------------------------------
  describe 'GetTrends' do
    def trends
      logic = ColonelAPI::Logic::Colonel::GetTrends.new(strategy_result_for(colonel), {})
      logic.raise_concerns
      logic.process
    end

    def clear_daily_metrics
      keys = Familia.dbclient.keys("#{Onetime::DailyMetric::KEY_PREFIX}:*")
      Familia.dbclient.del(*keys) unless keys.empty?
    end

    # Materialize the colonel FIRST — Customer.create! itself ticks the
    # signups metric (the instrumentation under test) — then zero the slate.
    before do
      colonel
      clear_daily_metrics
    end

    it 'counts a customer signup into the signups series (chokepoint wiring)' do
      create_customer(email: "signup-#{SecureRandom.hex(4)}@example.com")

      data = trends

      expect(data[:details][:series][:signups].last[:count]).to eq(1)
    end

    it 'returns 30 zero-filled days per series when nothing was collected' do
      data = trends

      expect(data[:details][:days]).to eq(30)
      %i[signups secrets_created].each do |metric|
        series = data[:details][:series][metric]
        expect(series.length).to eq(30)
        expect(series.map { |p| p[:count] }).to all(eq(0))
        expect(series.last[:date]).to eq(Time.now.utc.to_date.iso8601)
      end
    end

    it "reflects DailyMetric increments in today's bucket" do
      2.times { Onetime::DailyMetric.increment(:signups) }
      Onetime::DailyMetric.increment(:secrets_created)

      data = trends

      expect(data[:details][:series][:signups].last[:count]).to eq(2)
      expect(data[:details][:series][:secrets_created].last[:count]).to eq(1)
    end

    it 'reading trends writes NO audit event (CONTRACT 4)' do
      before_count = Onetime::AdminAuditEvent.count

      trends

      expect(Onetime::AdminAuditEvent.count).to eq(before_count)
    end

    it 'rejects non-colonel actors' do
      staff = create_customer(email: "staff-#{SecureRandom.hex(4)}@example.com", role: 'staff')

      logic = ColonelAPI::Logic::Colonel::GetTrends.new(strategy_result_for(staff), {})
      expect { logic.raise_concerns }.to raise_error(Onetime::Forbidden)
    end
  end
end

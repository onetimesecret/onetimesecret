# apps/api/colonel/spec/logic/colonel/list_organizations_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# Coverage for the DEFAULT_LIMIT behavior introduced in #4XXX: when no filters
# are active the roster is limited to the N most recently modified orgs via
# revrange (fast, no cache). When filters/search are active, the full roster
# is loaded and cached.
RSpec.describe ColonelAPI::Logic::Colonel::ListOrganizations do
  let(:colonel) do
    instance_double(
      Onetime::Customer,
      objid: 'cust_colonel',
      extid: 'ur_colonel',
      role: 'colonel',
      verified?: true,
      anonymous?: false,
    )
  end

  let(:strategy_result) do
    double(
      'StrategyResult',
      session: {},
      user: colonel,
      auth_method: 'sessionauth',
      metadata: {},
    )
  end

  let(:org1) do
    instance_double(
      Onetime::Organization,
      objid: 'org1',
      extid: 'on_org1',
      display_name: 'Acme Corp',
      contact_email: 'contact@acme.test',
      owner_id: 'cust1',
      owner: instance_double(Onetime::Customer, email: 'owner@acme.test'),
      member_count: 3,
      domain_count: 1,
      is_default: 'false',
      created: 1700000000,
      updated: 1700003600,
      planid: 'identity_plus_v1',
      stripe_customer_id: 'cus_123',
      stripe_subscription_id: 'sub_123',
      subscription_status: 'active',
      subscription_period_end: '2026-01-01',
      billing_email: 'billing@acme.test',
    )
  end

  let(:org2) do
    instance_double(
      Onetime::Organization,
      objid: 'org2',
      extid: 'on_org2',
      display_name: 'Beta Inc',
      contact_email: 'contact@beta.test',
      owner_id: 'cust2',
      owner: instance_double(Onetime::Customer, email: 'owner@beta.test'),
      member_count: 1,
      domain_count: 0,
      is_default: 'true',
      created: 1700001000,
      updated: nil,
      planid: nil,
      stripe_customer_id: nil,
      stripe_subscription_id: nil,
      subscription_status: nil,
      subscription_period_end: nil,
      billing_email: nil,
    )
  end

  let(:instances_double) do
    instance_double('Familia::SortedSet').tap do |ss|
      allow(ss).to receive(:to_a).and_return(%w[org1 org2])
      allow(ss).to receive(:revrange).and_return(%w[org2 org1])
    end
  end

  def logic_for(params = {})
    described_class.new(strategy_result, params)
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT).to receive(:le)

    allow(Onetime::Organization).to receive(:instances).and_return(instances_double)
    allow(Onetime::Organization).to receive(:load_multi).and_return([org1, org2])

    allow(Billing::BillingService).to receive(:compute_sync_status).and_return('unknown')
    allow(Billing::BillingService).to receive(:compute_sync_status_reason).and_return(nil)

    # Stub cache reads/writes
    allow(Familia).to receive(:now).and_return(Time.at(1700010000))
    allow(Familia).to receive(:dbclient).and_return(
      instance_double('Redis', get: nil, setex: true),
    )
  end

  describe 'DEFAULT_LIMIT behavior (no filters active)' do
    it 'uses revrange to load only the top N orgs by recency' do
      logic = logic_for({})
      logic.raise_concerns
      logic.process

      expect(instances_double).to have_received(:revrange)
        .with(0, described_class::DEFAULT_LIMIT - 1)
      expect(instances_double).not_to have_received(:to_a)
    end

    it 'skips the cache entirely for the default unfiltered load' do
      logic = logic_for({})
      logic.raise_concerns
      data = logic.process

      # No cache hit (never consulted), no cache write
      expect(data[:details][:cache][:cached]).to be(false)
    end

    it 'returns organizations sorted by created descending' do
      # org2 created at 1700001000, org1 at 1700000000 - org2 should come first
      logic = logic_for({})
      logic.raise_concerns
      data = logic.process

      orgs = data[:details][:organizations]
      expect(orgs.first[:extid]).to eq('on_org2')
      expect(orgs.last[:extid]).to eq('on_org1')
    end
  end

  describe 'filtered behavior (filters active)' do
    it 'loads the full roster via to_a when status_filter is present' do
      logic = logic_for('status' => 'active')
      logic.raise_concerns
      logic.process

      expect(instances_double).to have_received(:to_a)
      expect(instances_double).not_to have_received(:revrange)
    end

    it 'loads the full roster via to_a when sync_status_filter is present' do
      logic = logic_for('sync_status' => 'potentially_stale')
      logic.raise_concerns
      logic.process

      expect(instances_double).to have_received(:to_a)
    end

    it 'loads the full roster via to_a when search_term is present' do
      logic = logic_for('search' => 'acme')
      logic.raise_concerns
      logic.process

      expect(instances_double).to have_received(:to_a)
    end

    it 'writes to the cache after a filtered load' do
      db = instance_double('Redis', get: nil, setex: true)
      allow(Familia).to receive(:dbclient).and_return(db)

      logic = logic_for('status' => 'active')
      logic.raise_concerns
      logic.process

      expect(db).to have_received(:setex).with(
        described_class::CACHE_KEY,
        described_class::CACHE_TTL,
        kind_of(String),
      )
    end

    it 'reads from the cache on subsequent filtered requests' do
      cached_payload = {
        generated_at: 1700005000,
        organizations: [
          { org_id: 'org1', extid: 'on_org1', created: 1700000000 },
        ],
      }.to_json

      db = instance_double('Redis', get: cached_payload, setex: true)
      allow(Familia).to receive(:dbclient).and_return(db)

      logic = logic_for('status' => 'active')
      logic.raise_concerns
      data = logic.process

      expect(data[:details][:cache][:cached]).to be(true)
      expect(data[:details][:cache][:generated_at]).to eq(1_700_005_000)
      expect(instances_double).not_to have_received(:to_a)
    end
  end

  describe '#active_filters? predicate' do
    it 'returns false when all filters are nil or empty' do
      logic = logic_for({})
      logic.raise_concerns

      # Access via send since it's private
      expect(logic.send(:active_filters?)).to be(false)
    end

    it 'returns true when status_filter is present' do
      logic = logic_for('status' => 'active')
      logic.raise_concerns
      expect(logic.send(:active_filters?)).to be(true)
    end

    it 'returns true when sync_status_filter is present' do
      logic = logic_for('sync_status' => 'synced')
      logic.raise_concerns
      expect(logic.send(:active_filters?)).to be(true)
    end

    it 'returns true when search_term is present' do
      logic = logic_for('search' => 'test')
      logic.raise_concerns
      expect(logic.send(:active_filters?)).to be(true)
    end

    it 'returns false for empty string filters' do
      logic = logic_for('status' => '', 'sync_status' => '', 'search' => '')
      logic.raise_concerns
      expect(logic.send(:active_filters?)).to be(false)
    end

    it 'returns false for whitespace-only search' do
      logic = logic_for('search' => '   ')
      logic.raise_concerns
      # search_term is stripped in process_params, so it becomes empty
      expect(logic.send(:active_filters?)).to be(false)
    end
  end

  describe 'refresh bypass' do
    it 'skips the cache read when refresh param is truthy' do
      cached_payload = {
        generated_at: 1700005000,
        organizations: [{ org_id: 'cached', extid: 'on_cached', created: 1700000000 }],
      }.to_json

      db = instance_double('Redis', get: cached_payload, setex: true)
      allow(Familia).to receive(:dbclient).and_return(db)

      logic = logic_for('status' => 'active', 'refresh' => 'true')
      logic.raise_concerns
      data = logic.process

      # Should have loaded fresh data, not used the cache
      expect(instances_double).to have_received(:to_a)
      expect(data[:details][:cache][:cached]).to be(false)
    end
  end

  describe 'response envelope' do
    it 'includes pagination, filters, and cache state' do
      logic = logic_for({})
      logic.raise_concerns
      data = logic.process

      expect(data[:details]).to include(:organizations, :pagination, :filters, :cache)
      expect(data[:details][:pagination]).to include(:page, :per_page, :total_count, :total_pages)
      expect(data[:details][:filters]).to include(:status, :sync_status, :search)
      expect(data[:details][:cache]).to include(:cached, :generated_at, :ttl)
    end
  end
end

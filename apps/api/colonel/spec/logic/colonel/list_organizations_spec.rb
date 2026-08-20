# apps/api/colonel/spec/logic/colonel/list_organizations_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# Coverage for the split roster paths: when no filters are active only the
# requested page's org ids are loaded via revrange (fast, no cache) while
# total_count comes from the sorted set cardinality, so pagination spans the
# full population. When filters/search are active, the full roster is loaded
# (and cached), then filtered/sorted/paginated in memory.
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

  let(:org3) do
    instance_double(
      Onetime::Organization,
      objid: 'org3',
      extid: 'on_org3',
      display_name: 'Gamma LLC',
      contact_email: 'contact@gamma.test',
      owner_id: 'cust3',
      owner: instance_double(Onetime::Customer, email: 'owner@gamma.test'),
      member_count: 2,
      domain_count: 0,
      is_default: 'false',
      created: 1700002000,
      updated: 1700004000,
      planid: nil,
      stripe_customer_id: nil,
      stripe_subscription_id: nil,
      subscription_status: nil,
      subscription_period_end: nil,
      billing_email: nil,
    )
  end

  let(:orgs_by_id) { { 'org1' => org1, 'org2' => org2, 'org3' => org3 } }

  let(:instances_double) do
    instance_double('Familia::SortedSet').tap do |ss|
      allow(ss).to receive(:to_a).and_return(%w[org1 org2])
      allow(ss).to receive(:revrange).and_return(%w[org2 org1])
      allow(ss).to receive(:size).and_return(2)
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
    # Order-preserving, like the real load_multi (aligned with the input ids)
    allow(Onetime::Organization).to receive(:load_multi) do |ids|
      ids.map { |id| orgs_by_id[id] }
    end

    allow(Billing::BillingService).to receive(:compute_sync_status).and_return('unknown')
    allow(Billing::BillingService).to receive(:compute_sync_status_reason).and_return(nil)

    # Stub cache reads/writes
    allow(Familia).to receive(:now).and_return(Time.at(1700010000))
    allow(Familia).to receive(:dbclient).and_return(
      instance_double('Redis', get: nil, setex: true),
    )
  end

  describe 'paged behavior (no filters active)' do
    it 'loads only the requested page via revrange (default page 1)' do
      logic = logic_for({})
      logic.raise_concerns
      logic.process

      # Default per_page is 50, so page 1 is indices 0..49
      expect(instances_double).to have_received(:revrange).with(0, 49)
      expect(instances_double).not_to have_received(:to_a)
    end

    it 'derives the revrange window from page and per_page' do
      allow(instances_double).to receive(:revrange).with(10, 19).and_return([])

      logic = logic_for('page' => 2, 'per_page' => 10)
      logic.raise_concerns
      logic.process

      expect(instances_double).to have_received(:revrange).with(10, 19)
    end

    it 'reports total_count from the sorted set cardinality, not the page' do
      allow(instances_double).to receive(:size).and_return(120)

      logic = logic_for({})
      logic.raise_concerns
      data = logic.process

      pagination = data[:details][:pagination]
      expect(pagination[:total_count]).to eq(120)
      expect(pagination[:total_pages]).to eq(3) # ceil(120 / 50.0)
    end

    it 'skips the cache entirely for the default unfiltered load' do
      logic = logic_for({})
      logic.raise_concerns
      data = logic.process

      # No cache hit (never consulted), no cache write
      expect(data[:details][:cache][:cached]).to be(false)
    end

    it 'returns rows in revrange order (most recently modified first)' do
      logic = logic_for({})
      logic.raise_concerns
      data = logic.process

      orgs = data[:details][:organizations]
      expect(orgs.map { |o| o[:extid] }).to eq(%w[on_org2 on_org1])
    end

    it 'serializes a numeric subscription period end as a string' do
      allow(org1).to receive(:subscription_period_end).and_return(1_772_940_425)

      logic = logic_for({})
      logic.raise_concerns
      data = logic.process

      row = data[:details][:organizations].find { |org| org[:extid] == org1.extid }
      expect(row[:subscription_period_end]).to eq('1772940425')
    end

    it 'paginates a population larger than per_page without overlap' do
      allow(instances_double).to receive(:size).and_return(3)
      allow(instances_double).to receive(:revrange).with(0, 1).and_return(%w[org3 org2])
      allow(instances_double).to receive(:revrange).with(2, 3).and_return(%w[org1])

      page1 = logic_for('per_page' => 2)
      page1.raise_concerns
      data1 = page1.process

      page2 = logic_for('page' => 2, 'per_page' => 2)
      page2.raise_concerns
      data2 = page2.process

      rows1 = data1[:details][:organizations].map { |o| o[:extid] }
      rows2 = data2[:details][:organizations].map { |o| o[:extid] }

      expect(data1[:details][:pagination][:total_count]).to eq(3)
      expect(data1[:details][:pagination][:total_pages]).to eq(2)
      expect(rows1).to eq(%w[on_org3 on_org2])
      expect(rows2).to eq(%w[on_org1])
      expect(rows1 & rows2).to be_empty
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

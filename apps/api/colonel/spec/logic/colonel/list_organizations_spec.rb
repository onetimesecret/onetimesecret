# apps/api/colonel/spec/logic/colonel/list_organizations_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'colonel/logic'

# Coverage for the split roster paths: when no filters are active only the
# requested page's org ids are loaded via revrange while total_count comes from
# the sorted set cardinality, so pagination spans the full population. When
# filters/search are active the candidate set is BOUNDED — the newest-first
# instances window plus, for search, the exact-id lookups and the two index
# HSCANs, tiered so an email-shaped term the indexes answer never reads the
# window — then filtered/sorted/paginated in memory, with `capped` reporting
# whenever a bound that actually ran stopped short of the population. The
# full-fleet load and the roster cache are gone (they pinned production on
# every search).
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

  let(:owners_by_id) do
    {
      'cust1' => instance_double(Onetime::Customer, objid: 'cust1', email: 'owner@acme.test'),
      'cust2' => instance_double(Onetime::Customer, objid: 'cust2', email: 'owner@beta.test'),
      'cust3' => instance_double(Onetime::Customer, objid: 'cust3', email: 'owner@gamma.test'),
    }
  end

  let(:instances_double) do
    instance_double('Familia::SortedSet').tap do |ss|
      allow(ss).to receive(:to_a).and_return(%w[org1 org2])
      allow(ss).to receive(:revrange).and_return(%w[org2 org1])
      allow(ss).to receive(:size).and_return(2)
    end
  end

  # The two `field -> objid` index hashes the search path HSCANs. Default to
  # empty scans so the window-only tests isolate the instances read.
  let(:org_dbclient)  { double('OrgRedis') }
  let(:cust_dbclient) { double('CustRedis') }
  let(:window_limit)  { described_class::FILTER_WINDOW_LIMIT }

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
    allow(Onetime::Customer).to receive(:load_multi) do |ids|
      ids.map { |id| owners_by_id[id] }
    end

    # Search-path collaborators: exact-id lookups miss and both index scans
    # come back empty unless a test says otherwise.
    allow(Onetime::Organization).to receive(:find_by_extid).and_return(nil)
    allow(Onetime::Organization).to receive(:load).and_return(nil)
    allow(Onetime::Organization).to receive(:contact_email_index)
      .and_return(double('OrgEmailIndex', dbkey: 'organization:contact_email_index'))
    allow(Onetime::Organization).to receive(:dbclient).and_return(org_dbclient)
    allow(org_dbclient).to receive(:hscan).and_return(['0', []])
    allow(Onetime::Customer).to receive(:email_index)
      .and_return(double('CustEmailIndex', dbkey: 'customer:email_index'))
    allow(Onetime::Customer).to receive(:dbclient).and_return(cust_dbclient)
    allow(cust_dbclient).to receive(:hscan).and_return(['0', []])

    allow(Billing::BillingService).to receive(:compute_sync_status).and_return('unknown')
    allow(Billing::BillingService).to receive(:compute_sync_status_reason).and_return(nil)
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
      data  = logic.process

      pagination = data[:details][:pagination]
      expect(pagination[:total_count]).to eq(120)
      expect(pagination[:total_pages]).to eq(3) # ceil(120 / 50.0)
    end

    it 'is never capped: the page is exact and total_count is the cardinality' do
      logic = logic_for({})
      logic.raise_concerns
      data  = logic.process

      expect(data[:details][:pagination][:capped]).to be(false)
    end

    it 'batch-loads the page owners instead of one load per row' do
      logic = logic_for({})
      logic.raise_concerns
      data  = logic.process

      expect(Onetime::Customer).to have_received(:load_multi).once.with(%w[cust2 cust1])
      emails = data[:details][:organizations].map { |o| o[:owner_email] }
      expect(emails).to eq(%w[owner@beta.test owner@acme.test])
    end

    it 'returns rows in revrange order (most recently modified first)' do
      logic = logic_for({})
      logic.raise_concerns
      data  = logic.process

      orgs = data[:details][:organizations]
      expect(orgs.map { |o| o[:extid] }).to eq(%w[on_org2 on_org1])
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
    it 'reads the newest-first window, never the whole set, when status_filter is present' do
      logic = logic_for('status' => 'active')
      logic.raise_concerns
      data  = logic.process

      expect(instances_double).to have_received(:revrange).with(0, window_limit - 1)
      expect(instances_double).not_to have_received(:to_a)
      expect(data[:details][:organizations].map { |o| o[:extid] }).to eq(%w[on_org1])
    end

    it 'reads the window when sync_status_filter is present and filters on the computed status' do
      allow(Billing::BillingService).to receive(:compute_sync_status) do |org|
        org.objid == 'org2' ? 'potentially_stale' : 'synced'
      end

      logic = logic_for('sync_status' => 'potentially_stale')
      logic.raise_concerns
      data  = logic.process

      expect(instances_double).to have_received(:revrange).with(0, window_limit - 1)
      expect(instances_double).not_to have_received(:to_a)
      expect(data[:details][:organizations].map { |o| o[:extid] }).to eq(%w[on_org2])
    end

    it 'is not capped when the population fits the window' do
      logic = logic_for('status' => 'active')
      logic.raise_concerns
      data  = logic.process

      expect(data[:details][:pagination][:capped]).to be(false)
    end

    it 'reports capped when the population is larger than the window' do
      allow(instances_double).to receive(:size).and_return(window_limit + 1)

      logic = logic_for('status' => 'active')
      logic.raise_concerns
      data  = logic.process

      expect(data[:details][:pagination][:capped]).to be(true)
    end

    it 'never consults a roster cache' do
      expect(Familia).not_to receive(:dbclient)

      logic = logic_for('status' => 'active')
      logic.raise_concerns
      logic.process
    end

    it 'sorts filtered rows created-descending and counts only the matches' do
      allow(instances_double).to receive(:revrange).and_return(%w[org1 org3 org2])
      allow(instances_double).to receive(:size).and_return(3)

      logic = logic_for('sync_status' => 'unknown')
      logic.raise_concerns
      data  = logic.process

      expect(data[:details][:organizations].map { |o| o[:extid] }).to eq(%w[on_org3 on_org2 on_org1])
      expect(data[:details][:pagination][:total_count]).to eq(3)
    end
  end

  describe 'search' do
    it 'matches display_name within the window (case-insensitive)' do
      logic = logic_for('search' => 'ACME')
      logic.raise_concerns
      data  = logic.process

      expect(instances_double).to have_received(:revrange).with(0, window_limit - 1)
      expect(data[:details][:organizations].map { |o| o[:extid] }).to eq(%w[on_org1])
    end

    it 'scans the contact_email index and the window for a plain term, never the customer index' do
      logic = logic_for('search' => 'acme')
      logic.raise_concerns
      logic.process

      expect(org_dbclient).to have_received(:hscan)
      expect(instances_double).to have_received(:revrange).with(0, window_limit - 1)
      expect(cust_dbclient).not_to have_received(:hscan)
    end

    it 'still reads the window for a plain term the contact_email index answered (display_name has no index)' do
      allow(org_dbclient).to receive(:hscan).and_return(['0', [['contact@gamma.test', 'org3']]])

      logic = logic_for('search' => 'gamma')
      logic.raise_concerns
      data  = logic.process

      expect(instances_double).to have_received(:revrange).with(0, window_limit - 1)
      expect(data[:details][:organizations].map { |o| o[:extid] }).to eq(%w[on_org3])
    end

    it 'resolves an exact extid through the unique index and skips every scan' do
      allow(Onetime::Organization).to receive(:find_by_extid).with('on_org3').and_return(org3)
      # The unique-index load already existence-checked; a recheck on another
      # pooled connection could false-negative and drop the hit.
      expect(org3).not_to receive(:exists?)

      logic = logic_for('search' => 'on_org3')
      logic.raise_concerns
      data  = logic.process

      expect(data[:details][:organizations].map { |o| o[:extid] }).to eq(%w[on_org3])
      expect(data[:details][:pagination][:capped]).to be(false)
      expect(instances_double).not_to have_received(:revrange)
      expect(org_dbclient).not_to have_received(:hscan)
      expect(cust_dbclient).not_to have_received(:hscan)
    end

    it 'HSCANs the contact_email index with an escaped, case-insensitive glob' do
      captured = nil
      allow(org_dbclient).to receive(:hscan) do |dbkey, cursor, **opts|
        captured = [dbkey, cursor, opts]
        ['0', [['contact@gamma.test', 'org3']]]
      end
      allow(instances_double).to receive(:revrange).and_return([])

      logic = logic_for('search' => 'Gam[m]a')
      logic.raise_concerns
      data  = logic.process

      expect(captured[0]).to eq('organization:contact_email_index')
      expect(captured[1]).to eq('0')
      expect(captured[2][:match]).to eq('*[gG][aA][mM]\\[[mM]\\][aA]*')
      expect(captured[2][:count]).to eq(described_class::SCAN_COUNT)
      # The index candidate still has to pass the Ruby-side predicate.
      expect(data[:details][:organizations].map { |o| o[:extid] }).to eq([])
    end

    it 'includes contact_email index hits that match' do
      allow(org_dbclient).to receive(:hscan).and_return(['0', [['contact@gamma.test', 'org3']]])

      logic = logic_for('search' => 'contact@gamma')
      logic.raise_concerns
      data  = logic.process

      expect(data[:details][:organizations].map { |o| o[:extid] }).to eq(%w[on_org3])
    end

    it 'settles an email-shaped term on the index hit without reading the window' do
      allow(org_dbclient).to receive(:hscan).and_return(['0', [['contact@gamma.test', 'org3']]])
      allow(instances_double).to receive(:size).and_return(window_limit + 1)

      logic = logic_for('search' => 'contact@gamma')
      logic.raise_concerns
      data  = logic.process

      expect(data[:details][:organizations].map { |o| o[:extid] }).to eq(%w[on_org3])
      expect(instances_double).not_to have_received(:revrange)
      # The window was never read, so a population larger than it is not a cap.
      expect(data[:details][:pagination][:capped]).to be(false)
    end

    it 'falls back to the window for an email-shaped term neither index answers' do
      allow(instances_double).to receive(:size).and_return(window_limit + 1)

      logic = logic_for('search' => 'billing@acme')
      logic.raise_concerns
      data  = logic.process

      expect(org_dbclient).to have_received(:hscan)
      expect(cust_dbclient).to have_received(:hscan)
      expect(instances_double).to have_received(:revrange).with(0, window_limit - 1)
      # billing_email is matched in Ruby within the window only.
      expect(data[:details][:organizations].map { |o| o[:extid] }).to eq(%w[on_org1])
      expect(data[:details][:pagination][:capped]).to be(true)
    end

    it 'reports an index-settled email search as capped when the index scan itself stopped short' do
      allow(org_dbclient).to receive(:hscan).and_return(['7', [['contact@gamma.test', 'org3']]])

      logic = logic_for('search' => 'contact@gamma')
      logic.raise_concerns
      data  = logic.process

      expect(instances_double).not_to have_received(:revrange)
      expect(data[:details][:pagination][:capped]).to be(true)
    end

    it 'matches organizations OWNED by a customer whose email matches' do
      allow(cust_dbclient).to receive(:hscan).and_return(['0', [['owner@gamma.test', 'cust3']]])
      allow(owners_by_id['cust3']).to receive(:organization_instances).and_return([org3, org1])
      allow(instances_double).to receive(:revrange).and_return([])

      logic = logic_for('search' => 'owner@gamma')
      logic.raise_concerns
      data  = logic.process

      # org1 is a membership, not an ownership (owner_id cust1) — excluded.
      expect(data[:details][:organizations].map { |o| o[:extid] }).to eq(%w[on_org3])
      # The owner index answered, so the window is never read.
      expect(instances_double).not_to have_received(:revrange)
    end

    it 'caps the owner-email resolution and reports it' do
      entries = (1..(described_class::OWNER_MATCH_LIMIT + 1)).map { |i| ["u#{i}@x.test", "c#{i}"] }
      allow(cust_dbclient).to receive(:hscan).and_return(['0', entries])
      allow(Onetime::Customer).to receive(:load_multi) do |ids|
        expect(ids.size).to eq(described_class::OWNER_MATCH_LIMIT)
        []
      end

      logic = logic_for('search' => '@x.test')
      logic.raise_concerns
      data  = logic.process

      expect(data[:details][:pagination][:capped]).to be(true)
    end

    it 'stops a contact_email scan at the round cap and reports it' do
      allow(org_dbclient).to receive(:hscan).and_return(['7', []])
      allow(instances_double).to receive(:revrange).and_return([])

      logic = logic_for('search' => 'nobody')
      logic.raise_concerns
      data  = logic.process

      expect(org_dbclient).to have_received(:hscan).exactly(described_class::SEARCH_SCAN_ROUNDS).times
      expect(data[:details][:pagination][:capped]).to be(true)
    end

    it 'composes search with the status filter' do
      logic = logic_for('search' => 'test', 'status' => 'active')
      logic.raise_concerns
      data  = logic.process

      expect(data[:details][:organizations].map { |o| o[:extid] }).to eq(%w[on_org1])
    end

    it 'de-duplicates an org found by more than one path' do
      allow(org_dbclient).to receive(:hscan).and_return(['0', [['contact@acme.test', 'org1']]])

      logic = logic_for('search' => 'acme')
      logic.raise_concerns
      data  = logic.process

      expect(data[:details][:organizations].map { |o| o[:extid] }).to eq(%w[on_org1])
      expect(data[:details][:pagination][:total_count]).to eq(1)
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

  describe 'legacy refresh param' do
    it 'is accepted and ignored (there is no cache to bypass)' do
      logic = logic_for('status' => 'active', 'refresh' => 'true')
      logic.raise_concerns
      data  = logic.process

      expect(instances_double).to have_received(:revrange).with(0, window_limit - 1)
      expect(data[:details]).not_to have_key(:cache)
    end
  end

  describe 'response envelope' do
    it 'includes pagination (with capped) and the filter echo, and no cache block' do
      logic = logic_for({})
      logic.raise_concerns
      data  = logic.process

      expect(data[:details]).to include(:organizations, :pagination, :filters)
      expect(data[:details]).not_to have_key(:cache)
      expect(data[:details][:pagination]).to include(:page, :per_page, :total_count, :total_pages, :capped)
      expect(data[:details][:filters]).to include(:status, :sync_status, :search)
    end
  end
end

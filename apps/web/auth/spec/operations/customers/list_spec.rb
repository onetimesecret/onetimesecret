# apps/web/auth/spec/operations/customers/list_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::List.
#
# Covers the headline behavior: index-backed pagination (ZREVRANGE over
# Customer.instances, loading only the page — NOT load-all-then-slice),
# per_page clamping, index-backed role filtering, and the bounded email
# search (cursor HSCAN over the email_index with an escaped glob).
#
# Run: pnpm run test:rspec apps/web/auth/spec/operations/customers/list_spec.rb

require 'spec_helper'
require 'auth/operations/customers/list'

RSpec.describe Auth::Operations::Customers::List do
  let(:instances) { double('instances') }

  before { allow(Onetime::Customer).to receive(:instances).and_return(instances) }

  describe 'unfiltered pagination (the template)' do
    it 'reads exactly one page via revrange and loads only that page' do
      allow(instances).to receive(:element_count).and_return(7)
      allow(instances).to receive(:revrange).with(2, 3).and_return(%w[oid3 oid4])
      c3 = double('c3', objid: 'oid3')
      c4 = double('c4', objid: 'oid4')
      allow(Onetime::Customer).to receive(:load_multi).with(%w[oid3 oid4]).and_return([c3, c4])

      result = described_class.new(page: 2, per_page: 2).call

      expect(result.customers).to eq([c3, c4])
      expect(result.total_count).to eq(7)
      expect(result.total_pages).to eq(4) # ceil(7 / 2)
      # Index-backed: revrange for the page window, never a full members load.
      expect(instances).to have_received(:revrange).with(2, 3)
    end

    it 'clamps per_page to MAX_PER_PAGE' do
      allow(instances).to receive(:element_count).and_return(0)
      allow(instances).to receive(:revrange).and_return([])
      allow(Onetime::Customer).to receive(:load_multi).and_return([])

      result = described_class.new(page: 1, per_page: 500).call

      expect(result.per_page).to eq(described_class::MAX_PER_PAGE)
    end

    it 'clamps page to a minimum of 1' do
      allow(instances).to receive(:element_count).and_return(0)
      allow(instances).to receive(:revrange).with(0, 49).and_return([])
      allow(Onetime::Customer).to receive(:load_multi).and_return([])

      result = described_class.new(page: 0).call

      expect(result.page).to eq(1)
    end
  end

  describe 'role filter' do
    it 'reads the role_index via a bounded cursor SSCAN (never a blocking SMEMBERS)' do
      role_set = double('role_set', dbkey: 'customer:role_index:admin')
      dbclient = double('dbclient')
      allow(Onetime::Customer).to receive(:role_index_for).with('admin').and_return(role_set)
      allow(Onetime::Customer).to receive(:dbclient).and_return(dbclient)
      allow(dbclient).to receive(:sscan_each).and_yield('o')
      c = double('c', role: 'admin', created: 100, objid: 'o')
      allow(Onetime::Customer).to receive(:load_multi).with(['o']).and_return([c])
      # The #2211 residual: the filtered path must NOT do the blocking, load-all
      # find_all_by_role (SMEMBERS + load_multi of the whole set) anymore.
      expect(Onetime::Customer).not_to receive(:find_all_by_role)

      result = described_class.new(role: 'admin').call

      expect(dbclient).to have_received(:sscan_each)
      expect(result.customers).to eq([c])
      expect(result.total_count).to eq(1)
      expect(result.role).to eq('admin')
      # Scan stayed under the cap, so total_count is exact.
      expect(result.capped).to be(false)
    end

    it 'caps the request-path role scan at ROLE_FILTER_SCAN_LIMIT (never loads the whole set)' do
      limit    = described_class::ROLE_FILTER_SCAN_LIMIT
      role_set = double('role_set', dbkey: 'customer:role_index:customer')
      dbclient = double('dbclient')
      allow(Onetime::Customer).to receive(:role_index_for).with('customer').and_return(role_set)
      allow(Onetime::Customer).to receive(:dbclient).and_return(dbclient)
      # Yield more members than the cap; the op must stop scanning at the cap.
      allow(dbclient).to receive(:sscan_each) do |_key, **_opts, &blk|
        (limit + 25).times { |i| blk.call("o#{i}") }
      end
      loaded = nil
      allow(Onetime::Customer).to receive(:load_multi) { |ids| loaded = ids; [] }

      result = described_class.new(role: 'customer', per_page: 10).call

      expect(loaded.size).to eq(limit)
      # Scan hit the cap, so total_count understates the population: flag it.
      expect(result.capped).to be(true)
    end

    it 'treats a blank role as no filter (never touches the role_index)' do
      allow(instances).to receive(:element_count).and_return(0)
      allow(instances).to receive(:revrange).and_return([])
      allow(Onetime::Customer).to receive(:load_multi).and_return([])
      expect(Onetime::Customer).not_to receive(:role_index_for)

      result = described_class.new(role: '   ').call

      expect(result.role).to be_nil
    end
  end

  describe 'email search' do
    let(:email_index) { double('email_index', dbkey: 'customer:email_index') }
    let(:dbclient) { double('dbclient') }

    before do
      allow(Onetime::Customer).to receive(:email_index).and_return(email_index)
      allow(Onetime::Customer).to receive(:dbclient).and_return(dbclient)
      # The exact extid/objid lookups run on every search; default them to
      # misses so the email-substring tests isolate the HSCAN path.
      allow(Onetime::Customer).to receive(:find_by_extid).and_return(nil)
      allow(Onetime::Customer).to receive(:find_by_identifier).and_return(nil)
    end

    it 'cursor-HSCANs the email index with an escaped, lowercased glob' do
      captured = nil
      allow(dbclient).to receive(:hscan) do |dbkey, cursor, **opts|
        captured = [dbkey, cursor, opts]
        ['0', [['alice@example.com', 'oid1']]]
      end
      cust = double('cust', role: 'customer', created: 100, objid: 'oid1')
      allow(Onetime::Customer).to receive(:load_multi).with(['oid1']).and_return([cust])
      # Search never touches instances or the role index.
      expect(instances).not_to receive(:revrange)

      result = described_class.new(search: 'Ali[c]e*').call

      expect(captured[0]).to eq('customer:email_index')
      # Lowercased AND glob metacharacters escaped — user input is always a
      # literal substring, never pattern syntax.
      expect(captured[2][:match]).to eq('*ali\\[c\\]e\\**')
      expect(result.customers).to eq([cust])
      expect(result.total_count).to eq(1)
      # Cursor exhausted under the cap → total_count is exact, not capped.
      expect(result.capped).to be(false)
    end

    it 'caps collected matches at SEARCH_MATCH_LIMIT' do
      limit = described_class::SEARCH_MATCH_LIMIT
      # One giant HSCAN page exceeding the cap, cursor exhausted.
      entries = (0...(limit + 50)).map { |i| ["u#{i}@example.com", "oid#{i}"] }
      allow(dbclient).to receive(:hscan).and_return(['0', entries])
      loaded = nil
      allow(Onetime::Customer).to receive(:load_multi) { |ids| loaded = ids; [] }

      result = described_class.new(search: 'example').call

      expect(loaded.size).to eq(limit)
      # Overflow sliced off the return even though the cursor finished → capped.
      expect(result.capped).to be(true)
    end

    it 'stops scanning after SEARCH_SCAN_ROUNDS round-trips even with no matches' do
      rounds = 0
      allow(dbclient).to receive(:hscan) do
        rounds += 1
        ['42', []] # cursor never reaches '0' — an adversarially huge index
      end
      allow(Onetime::Customer).to receive(:load_multi).with([]).and_return([])

      described_class.new(search: 'nomatch').call

      expect(rounds).to eq(described_class::SEARCH_SCAN_ROUNDS)
    end

    it 'flags capped when the round cap truncates a scan that still has matches' do
      # A selective term on an adversarially huge index: one match early, then
      # the cursor churns empty pages until SEARCH_SCAN_ROUNDS stops the walk.
      # Collected count stays far below SEARCH_MATCH_LIMIT, so a size >= cap
      # check would wrongly report "complete" — the round-cap exit is the only
      # truncation signal here (regression guard for that false negative).
      first = true
      allow(dbclient).to receive(:hscan) do
        entries = first ? [['hit@example.com', 'oid-hit']] : []
        first = false
        ['42', entries] # cursor never reaches '0'
      end
      cust = double('cust', role: 'customer', created: 100, objid: 'oid-hit')
      allow(Onetime::Customer).to receive(:load_multi).and_return([cust])

      result = described_class.new(search: 'hit').call

      expect(result.total_count).to be < described_class::SEARCH_MATCH_LIMIT
      expect(result.capped).to be(true)
    end

    it 'composes with the role filter (applied to the bounded match set)' do
      allow(dbclient).to receive(:hscan).and_return(
        ['0', [['a@example.com', 'oid1'], ['b@example.com', 'oid2']]],
      )
      admin = double('admin', role: 'admin', created: 200, objid: 'oid1')
      cust  = double('cust', role: 'customer', created: 100, objid: 'oid2')
      allow(Onetime::Customer).to receive(:load_multi).with(%w[oid1 oid2]).and_return([admin, cust])

      result = described_class.new(search: 'example', role: 'admin').call

      expect(result.customers).to eq([admin])
      expect(result.total_count).to eq(1)
    end

    it 'treats a blank search as no search (falls through to pagination)' do
      allow(instances).to receive(:element_count).and_return(0)
      allow(instances).to receive(:revrange).and_return([])
      allow(Onetime::Customer).to receive(:load_multi).and_return([])
      expect(Onetime::Customer).not_to receive(:email_index)

      described_class.new(search: '   ').call
    end

    describe 'exact identifier lookups (extid / objid)' do
      before do
        # No email substring hits — isolate the identifier-lookup path.
        allow(dbclient).to receive(:hscan).and_return(['0', []])
        allow(Onetime::Customer).to receive(:load_multi).with([]).and_return([])
      end

      it 'resolves an exact extid via find_by_extid and includes it' do
        cust = double('cust', role: 'customer', created: 100, objid: 'oid-x')
        allow(Onetime::Customer).to receive(:find_by_extid).with('ur1234s').and_return(cust)
        allow(Onetime::Customer).to receive(:find_by_identifier).with('ur1234s').and_return(nil)

        result = described_class.new(search: 'ur1234s').call

        expect(result.customers).to eq([cust])
        expect(result.total_count).to eq(1)
      end

      it 'resolves an exact objid via find_by_identifier and includes it' do
        cust = double('cust', role: 'customer', created: 100, objid: 'the-objid')
        allow(Onetime::Customer).to receive(:find_by_extid).with('the-objid').and_return(nil)
        allow(Onetime::Customer).to receive(:find_by_identifier).with('the-objid').and_return(cust)

        result = described_class.new(search: 'the-objid').call

        expect(result.customers).to eq([cust])
      end

      it 'dedupes an identifier hit already present in the email matches' do
        cust = double('cust', role: 'customer', created: 100, objid: 'oid-dup')
        # Email index yields the same customer the extid lookup resolves to.
        allow(dbclient).to receive(:hscan).and_return(['0', [['a@example.com', 'oid-dup']]])
        allow(Onetime::Customer).to receive(:load_multi).with(['oid-dup']).and_return([cust])
        allow(Onetime::Customer).to receive(:find_by_extid).and_return(cust)
        allow(Onetime::Customer).to receive(:find_by_identifier).and_return(nil)

        result = described_class.new(search: 'oid-dup').call

        expect(result.customers).to eq([cust])
        expect(result.total_count).to eq(1)
      end

      it 'degrades a lookup that raises on a malformed term to no match' do
        allow(Onetime::Customer).to receive(:find_by_extid).and_raise(StandardError, 'bad id')
        allow(Onetime::Customer).to receive(:find_by_identifier).and_raise(StandardError, 'bad id')

        result = described_class.new(search: '!!!').call

        expect(result.customers).to eq([])
        expect(result.total_count).to eq(0)
      end

      it 'applies the role filter to identifier hits too' do
        admin = double('admin', role: 'admin', created: 100, objid: 'oid-a')
        allow(Onetime::Customer).to receive(:find_by_extid).and_return(admin)
        allow(Onetime::Customer).to receive(:find_by_identifier).and_return(nil)

        # Same extid hit, but filtered to a role it does not have -> excluded.
        result = described_class.new(search: 'ur1s', role: 'colonel').call

        expect(result.customers).to eq([])
      end
    end
  end
end

# apps/web/auth/spec/operations/customers/list_spec.rb
#
# frozen_string_literal: true

# Unit tests for Auth::Operations::Customers::List.
#
# Covers the headline behavior: index-backed pagination (ZREVRANGE over
# Customer.instances, loading only the page — NOT load-all-then-slice),
# per_page clamping, and index-backed role filtering via find_all_by_role.
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

      described_class.new(role: 'customer', per_page: 10).call

      expect(loaded.size).to eq(limit)
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
end

# spec/unit/onetime/membership_snapshot_spec.rb
#
# frozen_string_literal: true

# Run: tests/lanes/run unit --only spec/unit/onetime/membership_snapshot_spec.rb
require 'spec_helper'
require 'onetime/membership_snapshot'

RSpec.describe Onetime::MembershipSnapshot do
  let(:org_a) { instance_double(Onetime::Organization, objid: 'org-a') }
  let(:org_b) { instance_double(Onetime::Organization, objid: 'org-b') }
  let(:customer) { double('customer', objid: 'cust-1', organization_instances: [org_a, org_b]) }

  after { described_class.close }

  describe '.for' do
    it 'hands out one snapshot per customer while the store is open' do
      described_class.open
      other = double('other customer', objid: 'cust-2')

      expect(described_class.for(customer)).to be(described_class.for(customer))
      expect(described_class.for(other)).not_to be(described_class.for(customer))
    end

    it 'hands out a fresh snapshot each time with no store open' do
      expect(described_class.open?).to be(false)
      expect(described_class.for(customer)).not_to be(described_class.for(customer))
    end

    it 'does not keep a snapshot for a customer without an objid' do
      described_class.open
      unsaved = double('unsaved customer', objid: nil)

      expect(described_class.for(unsaved)).not_to be(described_class.for(unsaved))
    end

    it 'does not keep a snapshot for a customer that cannot name itself' do
      described_class.open
      nameless = double('nameless')

      expect(described_class.for(nameless)).not_to be(described_class.for(nameless))
    end
  end

  describe '.open' do
    it 'discards what an earlier request left on this fiber' do
      described_class.open
      first = described_class.for(customer)
      described_class.open

      expect(described_class.for(customer)).not_to be(first)
    end
  end

  describe '.close' do
    it 'leaves no store open' do
      described_class.open
      described_class.close

      expect(described_class.open?).to be(false)
    end
  end

  describe '.forget' do
    it 'drops the snapshot for that customer only' do
      described_class.open
      other   = double('other customer', objid: 'cust-2')
      mine    = described_class.for(customer)
      theirs  = described_class.for(other)

      described_class.forget(customer)

      expect(described_class.for(customer)).not_to be(mine)
      expect(described_class.for(other)).to be(theirs)
    end

    it 'accepts an objid' do
      described_class.open
      mine = described_class.for(customer)

      described_class.forget('cust-1')

      expect(described_class.for(customer)).not_to be(mine)
    end

    it 'is a no-op with no store open' do
      expect { described_class.forget(customer) }.not_to raise_error
    end
  end

  describe '.forget_all' do
    it 'drops every snapshot but keeps the store open' do
      described_class.open
      mine = described_class.for(customer)

      described_class.forget_all

      expect(described_class.open?).to be(true)
      expect(described_class.for(customer)).not_to be(mine)
    end
  end

  describe '#organizations' do
    it 'reads the membership list once' do
      expect(customer).to receive(:organization_instances).once.and_return([org_a, org_b])
      snapshot = described_class.new(customer)

      expect(snapshot.organizations).to eq([org_a, org_b])
      expect(snapshot.organizations).to eq([org_a, org_b])
    end
  end

  describe '#owner?' do
    it 'asks each organization once' do
      expect(org_a).to receive(:owner?).with(customer).once.and_return(true)
      expect(org_b).to receive(:owner?).with(customer).once.and_return(false)
      snapshot = described_class.new(customer)

      2.times do
        expect(snapshot.owner?(org_a)).to be(true)
        expect(snapshot.owner?(org_b)).to be(false)
      end
    end
  end

  describe '#membership' do
    it 'reads each membership record once, a missing one included' do
      record   = instance_double(Onetime::OrganizationMembership)
      expect(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
        .with('org-a', 'cust-1').once.and_return(record)
      expect(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
        .with('org-b', 'cust-1').once.and_return(nil)
      snapshot = described_class.new(customer)

      2.times do
        expect(snapshot.membership(org_a)).to be(record)
        expect(snapshot.membership(org_b)).to be_nil
      end
    end
  end

  describe '#memo' do
    it 'computes a key once, remembering nil' do
      snapshot = described_class.new(customer)
      calls    = 0

      3.times do
        snapshot.memo(:user_default) do
                  calls += 1
                  nil
        end
      end

      expect(calls).to eq(1)
      expect(snapshot.memo(:user_default) { :never }).to be_nil
      expect(snapshot.memo(:other) { :value }).to eq(:value)
    end
  end
end

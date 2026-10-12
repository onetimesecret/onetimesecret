# spec/unit/onetime/models/organization/chores/standardize_owner_id_spec.rb
#
# frozen_string_literal: true

# Unit tests for the standardize_owner_id housekeeping chore.
#
# Tests the created_by backfill logic with a mock object that mirrors the
# interface the chore expects. A full `save` is not stubbed, so calling it
# fails the example. The last group runs against the datastore to show the
# partial write keeps a concurrent edit (#4343).
#
# Run: pnpm run test:rspec spec/unit/onetime/models/organization/chores/standardize_owner_id_spec.rb

require 'spec_helper'

# Load the chore registration
require_relative '../../../../../../lib/onetime/models/organization/chores/standardize_owner_id'

RSpec.describe 'Organization chore: standardize_owner_id' do
  let(:chore) { Onetime::Organization.chores[:standardize_owner_id] }

  let(:mock_logger) do
    double('SemanticLogger').tap do |logger|
      allow(logger).to receive(:info) { |_msg, _payload = {}| nil }
      allow(logger).to receive(:warn) { |_msg, _payload = {}| nil }
    end
  end

  # Mock organization object with the interface the chore uses
  let(:org) do
    obj = instance_double(
      'Onetime::Organization',
      extid: 'org_test123',
      owner_id: current_owner_id,
      created_by: current_created_by
    )
    allow(obj).to receive(:created_by=)
    allow(obj).to receive(:save_fields).and_return(obj)
    obj
  end

  before do
    allow(Onetime).to receive(:get_logger).with('Chores').and_return(mock_logger)
  end

  describe 'chore registration' do
    let(:current_owner_id) { 'cust_abc' }
    let(:current_created_by) { 'cust_abc' }

    it 'is registered on Onetime::Organization' do
      expect(Onetime::Organization.chores).to have_key(:standardize_owner_id)
    end

    it 'is a callable block' do
      expect(chore).to respond_to(:call)
    end
  end

  describe 'Branch 1: created_by already in sync (silent no-op)' do
    context 'when both fields are equal' do
      let(:current_owner_id) { 'cust_abc' }
      let(:current_created_by) { 'cust_abc' }

      it 'returns nil (skips)' do
        expect(chore.call(org)).to be_nil
      end

      it 'does not call created_by=' do
        expect(org).not_to receive(:created_by=)
        chore.call(org)
      end

      it 'does not save' do
        expect(org).not_to receive(:save_fields)
        chore.call(org)
      end

      it 'does not log' do
        expect(mock_logger).not_to receive(:info)
        expect(mock_logger).not_to receive(:warn)
        chore.call(org)
      end
    end
  end

  describe 'Branch 2: created_by missing, owner_id present (backfill)' do
    let(:current_owner_id) { 'cust_abc' }
    let(:current_created_by) { nil }

    it 'sets created_by to owner_id value' do
      expect(org).to receive(:created_by=).with('cust_abc')
      chore.call(org)
    end

    it 'writes created_by alone' do
      expect(org).to receive(:save_fields).with(:created_by)
      chore.call(org)
    end

    it 'returns true' do
      expect(chore.call(org)).to be true
    end

    it 'logs the backfill at :info' do
      expect(mock_logger).to receive(:info).with(
        'Backfilling created_by from owner_id',
        hash_including(
          chore: :standardize_owner_id,
          org_extid: 'org_test123',
          owner_id: 'cust_abc'
        )
      )
      chore.call(org)
    end

    context 'when created_by is empty string' do
      let(:current_created_by) { '' }

      it 'treats empty string as missing and backfills' do
        expect(org).to receive(:created_by=).with('cust_abc')
        chore.call(org)
      end
    end
  end

  describe 'Branch 3a: both fields nil/empty (skip with warn)' do
    let(:current_owner_id) { nil }
    let(:current_created_by) { nil }

    it 'returns nil (skips)' do
      expect(chore.call(org)).to be_nil
    end

    it 'does not call created_by=' do
      expect(org).not_to receive(:created_by=)
      chore.call(org)
    end

    it 'does not save' do
      expect(org).not_to receive(:save_fields)
      chore.call(org)
    end

    it 'logs the skip at :warn' do
      expect(mock_logger).to receive(:warn).with(
        'Skipping organization with no owner_id or created_by',
        hash_including(
          chore: :standardize_owner_id,
          org_extid: 'org_test123'
        )
      )
      chore.call(org)
    end

    context 'when both are empty strings' do
      let(:current_owner_id) { '' }
      let(:current_created_by) { '' }

      it 'still warns and skips' do
        expect(mock_logger).to receive(:warn)
        expect(chore.call(org)).to be_nil
      end
    end
  end

  describe 'Branch 3b: both present but disagree (skip with warn)' do
    let(:current_owner_id) { 'cust_abc' }
    let(:current_created_by) { 'cust_xyz' }

    it 'returns nil (skips)' do
      expect(chore.call(org)).to be_nil
    end

    it 'does not overwrite either field' do
      expect(org).not_to receive(:created_by=)
      chore.call(org)
    end

    it 'does not save' do
      expect(org).not_to receive(:save_fields)
      chore.call(org)
    end

    it 'logs both values at :warn' do
      expect(mock_logger).to receive(:warn).with(
        'Skipping inconsistent owner_id and created_by',
        hash_including(
          chore: :standardize_owner_id,
          org_extid: 'org_test123',
          owner_id: 'cust_abc',
          created_by: 'cust_xyz'
        )
      )
      chore.call(org)
    end
  end

  describe 'Branch 3c: created_by present but owner_id missing (skip with warn)' do
    let(:current_owner_id) { nil }
    let(:current_created_by) { 'cust_abc' }

    it 'returns nil (skips)' do
      expect(chore.call(org)).to be_nil
    end

    it 'does not modify created_by' do
      expect(org).not_to receive(:created_by=)
      chore.call(org)
    end

    it 'does not save' do
      expect(org).not_to receive(:save_fields)
      chore.call(org)
    end

    it 'logs the skip at :warn' do
      expect(mock_logger).to receive(:warn).with(
        'Skipping organization with created_by but no owner_id',
        hash_including(
          chore: :standardize_owner_id,
          org_extid: 'org_test123',
          created_by: 'cust_abc'
        )
      )
      chore.call(org)
    end
  end

  describe 'whitespace handling' do
    context 'when owner_id has surrounding whitespace' do
      let(:current_owner_id) { '  cust_abc  ' }
      let(:current_created_by) { 'cust_abc' }

      it 'treats stripped values as equal (no-op)' do
        expect(org).not_to receive(:created_by=)
        expect(org).not_to receive(:save_fields)
        expect(mock_logger).not_to receive(:info)
        expect(mock_logger).not_to receive(:warn)
        chore.call(org)
      end
    end

    context 'when created_by is only whitespace' do
      let(:current_owner_id) { 'cust_abc' }
      let(:current_created_by) { '   ' }

      it 'treats as empty and backfills' do
        expect(org).to receive(:created_by=).with('cust_abc')
        chore.call(org)
      end
    end
  end

  # The point of the partial write (#4343): HousekeepingJob loads orgs in
  # batches, and an on-demand run can land while an org is being edited. A
  # whole-record save from the stale copy would undo that edit.
  describe 'against the datastore', :datastore do
    let(:suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }

    before do
      # Real loggers here: create! and load log under other names.
      allow(Onetime).to receive(:get_logger).and_call_original
      @owner = Onetime::Customer.create!(email: "owner_id_chore_#{suffix}@onetimesecret.com")
      @org   = Onetime::Organization.create!("Owner Chore #{suffix}", @owner)
      Familia.dbclient.hdel(@org.dbkey, 'created_by') # a pre-ADR-012 org
    end

    after do
      @org&.destroy!
      @owner&.destroy!
    end

    it 'keeps a field edited after the batch load and backfills created_by' do
      stale = Onetime::Organization.load(@org.identifier) # the batch load

      concurrent              = Onetime::Organization.load(@org.identifier)
      concurrent.display_name = "Renamed #{suffix}"
      concurrent.save_fields(:display_name)

      expect(chore.call(stale)).to be true

      reloaded = Onetime::Organization.load(@org.identifier)
      expect(reloaded.display_name).to eq("Renamed #{suffix}")
      expect(reloaded.created_by).to eq(@org.owner_id)
    end
  end
end

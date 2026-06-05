# spec/unit/onetime/models/organization/chores/ensure_member_through_models_spec.rb
#
# frozen_string_literal: true

# Unit tests for the ensure_member_through_models housekeeping chore.
#
# Tests the membership through-model backfill logic without requiring Redis
# or actual Organization instances. Uses an instance_double that mirrors
# the interface the chore expects.
#
# Five branches per member entry:
#   1. Through-model exists AND materialized      → silent no-op
#   2. Through-model exists, NOT materialized      → materialize only
#   3. Through-model missing, customer loadable    → create + materialize
#   4. Through-model missing, customer NOT loadable → warn (stale ZSET entry)
#   5. org.members empty                           → no-op
#
# Run: bundle exec rspec spec/unit/onetime/models/organization/chores/ensure_member_through_models_spec.rb

require 'spec_helper'

# Load the chore registration
require_relative '../../../../../../lib/onetime/models/organization/chores/ensure_member_through_models'

RSpec.describe 'Organization chore: ensure_member_through_models' do
  let(:chore) { Onetime::Organization.chores[:ensure_member_through_models] }

  let(:mock_logger) do
    double('SemanticLogger').tap do |logger|
      allow(logger).to receive(:info) { |_msg, _payload = {}| nil }
      allow(logger).to receive(:warn) { |_msg, _payload = {}| nil }
      allow(logger).to receive(:error) { |_msg, _payload = {}| nil }
    end
  end

  # Stub for org.members — responds to .to_a
  let(:members_set) { double('SortedSet', to_a: member_objids) }

  # Stub for org.entitlements — responds to .empty?
  let(:entitlements_list) { double('Entitlements', empty?: entitlements_empty) }
  let(:entitlements_empty) { false }

  # Stub for org.created — responds to .to_f
  let(:org_created) { double('Created', to_f: 1700000000.0) }

  let(:org) do
    obj = instance_double(
      'Onetime::Organization',
      objid: 'org_objid_123',
      extid: 'org_test123',
      owner_id: owner_objid,
      members: members_set,
      entitlements: entitlements_list,
      created: org_created,
    )
    allow(obj).to receive(:add_members_instance).and_return(nil)
    allow(obj).to receive(:materialize_standalone_entitlements!)
    obj
  end

  before do
    allow(Onetime).to receive(:get_logger).with('Chores').and_return(mock_logger)
  end

  # Default values — overridden per context
  let(:member_objids) { [] }
  let(:owner_objid) { 'cust_owner' }

  describe 'chore registration' do
    it 'is registered on Onetime::Organization' do
      expect(Onetime::Organization.chores).to have_key(:ensure_member_through_models)
    end

    it 'is a callable block' do
      expect(chore).to respond_to(:call)
    end
  end

  describe 'Branch 5: org.members empty (no-op)' do
    let(:member_objids) { [] }

    it 'returns nil' do
      expect(chore.call(org)).to be_nil
    end

    it 'does not log' do
      expect(mock_logger).not_to receive(:info)
      expect(mock_logger).not_to receive(:warn)
      chore.call(org)
    end
  end

  describe 'Branch 1: through-model exists AND materialized (silent no-op)' do
    let(:member_objids) { ['cust_a'] }

    let(:existing_membership) do
      double('Membership',
        entitlements_materialized?: true,
      )
    end

    before do
      allow(OT::OrganizationMembership).to receive(:find_by_org_customer)
        .with('org_objid_123', 'cust_a')
        .and_return(existing_membership)
    end

    it 'returns nil' do
      expect(chore.call(org)).to be_nil
    end

    it 'does not create a membership' do
      expect(org).not_to receive(:add_members_instance)
      chore.call(org)
    end

    it 'does not materialize' do
      expect(existing_membership).not_to receive(:materialize_for_role!)
      chore.call(org)
    end

    it 'does not log' do
      expect(mock_logger).not_to receive(:info)
      expect(mock_logger).not_to receive(:warn)
      chore.call(org)
    end
  end

  describe 'Branch 2: through-model exists, NOT materialized (materialize only)' do
    let(:member_objids) { ['cust_a'] }

    let(:existing_membership) do
      double('Membership',
        entitlements_materialized?: false,
      ).tap do |m|
        allow(m).to receive(:materialize_for_role!)
      end
    end

    before do
      allow(OT::OrganizationMembership).to receive(:find_by_org_customer)
        .with('org_objid_123', 'cust_a')
        .and_return(existing_membership)
    end

    it 'calls materialize_for_role! on the membership' do
      expect(existing_membership).to receive(:materialize_for_role!).with(org)
      chore.call(org)
    end

    it 'does not create a new membership' do
      expect(org).not_to receive(:add_members_instance)
      chore.call(org)
    end

    it 'returns true' do
      expect(chore.call(org)).to be true
    end

    it 'logs the materialization at :info' do
      expect(mock_logger).to receive(:info).with(
        'Materialized membership entitlements',
        hash_including(
          chore: :ensure_member_through_models,
          org_extid: 'org_test123',
          customer_objid: 'cust_a',
        ),
      )
      chore.call(org)
    end

    context 'when org.entitlements is empty' do
      let(:entitlements_empty) { true }

      it 'calls materialize_standalone_entitlements! before materializing membership' do
        expect(org).to receive(:materialize_standalone_entitlements!)
        expect(existing_membership).to receive(:materialize_for_role!).with(org)
        chore.call(org)
      end
    end

    context 'when org.entitlements is NOT empty' do
      let(:entitlements_empty) { false }

      it 'does not call materialize_standalone_entitlements!' do
        expect(org).not_to receive(:materialize_standalone_entitlements!)
        chore.call(org)
      end
    end
  end

  describe 'Branch 3: through-model missing, customer loadable (create + materialize)' do
    let(:member_objids) { ['cust_a'] }
    let(:owner_objid) { 'cust_owner' }

    let(:customer) do
      double('Customer', exists?: true)
    end

    let(:created_membership) do
      double('Membership',
        entitlements_materialized?: false,
      ).tap do |m|
        allow(m).to receive(:materialize_for_role!)
      end
    end

    before do
      allow(OT::OrganizationMembership).to receive(:find_by_org_customer)
        .with('org_objid_123', 'cust_a')
        .and_return(nil)
      allow(OT::Customer).to receive(:load)
        .with('cust_a')
        .and_return(customer)
      allow(org).to receive(:add_members_instance)
        .with(customer, through_attrs: hash_including(:role, :status, :joined_at))
        .and_return(created_membership)
    end

    it 'loads the customer' do
      expect(OT::Customer).to receive(:load).with('cust_a').and_return(customer)
      chore.call(org)
    end

    it 'creates a membership with correct attributes' do
      expect(org).to receive(:add_members_instance).with(
        customer,
        through_attrs: hash_including(
          role: 'member',
          status: 'active',
          joined_at: 1700000000.0,
        ),
      ).and_return(created_membership)
      chore.call(org)
    end

    it 'materializes the created membership' do
      expect(created_membership).to receive(:materialize_for_role!).with(org)
      chore.call(org)
    end

    it 'returns true' do
      expect(chore.call(org)).to be true
    end

    it 'logs the creation at :info' do
      expect(mock_logger).to receive(:info).with(
        'Created membership through-model',
        hash_including(
          chore: :ensure_member_through_models,
          org_extid: 'org_test123',
          customer_objid: 'cust_a',
          role: 'member',
        ),
      )
      chore.call(org)
    end

    it 'logs the materialization at :info' do
      expect(mock_logger).to receive(:info).with(
        'Materialized membership entitlements',
        hash_including(
          chore: :ensure_member_through_models,
          org_extid: 'org_test123',
          customer_objid: 'cust_a',
        ),
      )
      chore.call(org)
    end
  end

  describe 'Branch 4: through-model missing, customer NOT loadable (warn + skip)' do
    let(:member_objids) { ['cust_stale'] }

    before do
      allow(OT::OrganizationMembership).to receive(:find_by_org_customer)
        .with('org_objid_123', 'cust_stale')
        .and_return(nil)
    end

    context 'when Customer.load returns nil' do
      before do
        allow(OT::Customer).to receive(:load).with('cust_stale').and_return(nil)
      end

      it 'logs a warning about the stale ZSET entry' do
        expect(mock_logger).to receive(:warn).with(
          'Stale ZSET entry: customer not loadable',
          hash_including(
            chore: :ensure_member_through_models,
            org_extid: 'org_test123',
            customer_objid: 'cust_stale',
          ),
        )
        chore.call(org)
      end

      it 'does not create a membership' do
        expect(org).not_to receive(:add_members_instance)
        chore.call(org)
      end

      it 'returns nil' do
        expect(chore.call(org)).to be_nil
      end
    end

    context 'when customer exists? returns false' do
      let(:ghost_customer) { double('Customer', exists?: false) }

      before do
        allow(OT::Customer).to receive(:load).with('cust_stale').and_return(ghost_customer)
      end

      it 'logs a warning about the stale ZSET entry' do
        expect(mock_logger).to receive(:warn).with(
          'Stale ZSET entry: customer not loadable',
          hash_including(customer_objid: 'cust_stale'),
        )
        chore.call(org)
      end

      it 'does not create a membership' do
        expect(org).not_to receive(:add_members_instance)
        chore.call(org)
      end
    end
  end

  describe 'Role assignment' do
    let(:member_objids) { ['cust_owner'] }
    let(:owner_objid) { 'cust_owner' }

    let(:customer) { double('Customer', exists?: true) }
    let(:created_membership) do
      double('Membership', entitlements_materialized?: false).tap do |m|
        allow(m).to receive(:materialize_for_role!)
      end
    end

    before do
      allow(OT::OrganizationMembership).to receive(:find_by_org_customer)
        .with('org_objid_123', 'cust_owner')
        .and_return(nil)
      allow(OT::Customer).to receive(:load)
        .with('cust_owner')
        .and_return(customer)
      allow(org).to receive(:add_members_instance).and_return(created_membership)
    end

    context 'when customer_objid matches owner_id' do
      it 'assigns role "owner"' do
        expect(org).to receive(:add_members_instance).with(
          customer,
          through_attrs: hash_including(role: 'owner'),
        ).and_return(created_membership)
        chore.call(org)
      end
    end

    context 'when customer_objid does not match owner_id' do
      let(:member_objids) { ['cust_regular'] }

      before do
        allow(OT::OrganizationMembership).to receive(:find_by_org_customer)
          .with('org_objid_123', 'cust_regular')
          .and_return(nil)
        allow(OT::Customer).to receive(:load)
          .with('cust_regular')
          .and_return(customer)
      end

      it 'assigns role "member"' do
        expect(org).to receive(:add_members_instance).with(
          customer,
          through_attrs: hash_including(role: 'member'),
        ).and_return(created_membership)
        chore.call(org)
      end
    end
  end

  describe 'Org entitlements empty triggers materialization' do
    let(:member_objids) { ['cust_a'] }
    let(:entitlements_empty) { true }

    let(:existing_membership) do
      double('Membership', entitlements_materialized?: false).tap do |m|
        allow(m).to receive(:materialize_for_role!)
      end
    end

    before do
      allow(OT::OrganizationMembership).to receive(:find_by_org_customer)
        .with('org_objid_123', 'cust_a')
        .and_return(existing_membership)
    end

    it 'calls materialize_standalone_entitlements! on the org' do
      expect(org).to receive(:materialize_standalone_entitlements!)
      chore.call(org)
    end

    it 'then materializes the membership' do
      expect(existing_membership).to receive(:materialize_for_role!).with(org)
      chore.call(org)
    end
  end

  describe 'Idempotent re-run' do
    let(:member_objids) { ['cust_a'] }

    let(:materialized_membership) do
      double('Membership', entitlements_materialized?: true)
    end

    before do
      allow(OT::OrganizationMembership).to receive(:find_by_org_customer)
        .with('org_objid_123', 'cust_a')
        .and_return(materialized_membership)
    end

    it 'returns nil on first call (already materialized)' do
      expect(chore.call(org)).to be_nil
    end

    it 'returns nil on second call (still no-op)' do
      chore.call(org)
      expect(chore.call(org)).to be_nil
    end

    it 'never creates or materializes' do
      expect(org).not_to receive(:add_members_instance)
      expect(materialized_membership).not_to receive(:materialize_for_role!)
      chore.call(org)
      chore.call(org)
    end
  end

  describe 'Multiple members with mixed states' do
    let(:member_objids) { ['cust_owner', 'cust_existing', 'cust_missing', 'cust_stale'] }
    let(:owner_objid) { 'cust_owner' }
    let(:entitlements_empty) { false }

    # cust_owner: through-model exists, already materialized (Branch 1)
    let(:owner_membership) do
      double('OwnerMembership', entitlements_materialized?: true)
    end

    # cust_existing: through-model exists, NOT materialized (Branch 2)
    let(:existing_membership) do
      double('ExistingMembership', entitlements_materialized?: false).tap do |m|
        allow(m).to receive(:materialize_for_role!)
      end
    end

    # cust_missing: through-model missing, customer loadable (Branch 3)
    let(:missing_customer) { double('MissingCustomer', exists?: true) }
    let(:created_membership) do
      double('CreatedMembership', entitlements_materialized?: false).tap do |m|
        allow(m).to receive(:materialize_for_role!)
      end
    end

    # cust_stale: through-model missing, customer NOT loadable (Branch 4)

    before do
      allow(OT::OrganizationMembership).to receive(:find_by_org_customer)
        .with('org_objid_123', 'cust_owner')
        .and_return(owner_membership)
      allow(OT::OrganizationMembership).to receive(:find_by_org_customer)
        .with('org_objid_123', 'cust_existing')
        .and_return(existing_membership)
      allow(OT::OrganizationMembership).to receive(:find_by_org_customer)
        .with('org_objid_123', 'cust_missing')
        .and_return(nil)
      allow(OT::OrganizationMembership).to receive(:find_by_org_customer)
        .with('org_objid_123', 'cust_stale')
        .and_return(nil)

      allow(OT::Customer).to receive(:load).with('cust_missing').and_return(missing_customer)
      allow(OT::Customer).to receive(:load).with('cust_stale').and_return(nil)

      allow(org).to receive(:add_members_instance)
        .with(missing_customer, through_attrs: hash_including(role: 'member'))
        .and_return(created_membership)
    end

    it 'returns true (modifications were made)' do
      expect(chore.call(org)).to be true
    end

    it 'skips the already-materialized owner membership' do
      expect(owner_membership).not_to receive(:materialize_for_role!)
      chore.call(org)
    end

    it 'materializes the existing but unmaterialized membership' do
      expect(existing_membership).to receive(:materialize_for_role!).with(org)
      chore.call(org)
    end

    it 'creates a through-model for the missing but loadable customer' do
      expect(org).to receive(:add_members_instance)
        .with(missing_customer, through_attrs: hash_including(role: 'member'))
        .and_return(created_membership)
      chore.call(org)
    end

    it 'materializes the newly created membership' do
      expect(created_membership).to receive(:materialize_for_role!).with(org)
      chore.call(org)
    end

    it 'warns about the stale customer entry' do
      expect(mock_logger).to receive(:warn).with(
        'Stale ZSET entry: customer not loadable',
        hash_including(customer_objid: 'cust_stale'),
      )
      chore.call(org)
    end

    it 'does not attempt to create a membership for the stale entry' do
      expect(org).not_to receive(:add_members_instance).with(anything, through_attrs: hash_including(customer_objid: 'cust_stale'))
      chore.call(org)
    end
  end
end

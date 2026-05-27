# spec/unit/onetime/models/organization_membership/with_materialized_entitlements_spec.rb
#
# frozen_string_literal: true

# Unit tests for MembershipMaterializedEntitlements feature module (ADR-012 Stage 3)
#
# Covers:
#  1. ROLE_ENTITLEMENTS constant structure and hierarchy
#  2. materialize_for_role! method
#  3. can?() method with various entitlements
#  4. Operator grants/revokes (entitlements_grants, entitlements_revokes)
#  5. Role-based entitlement filtering
#
# Tests use the same FakeSet/FakeHashKey pattern as the org-level spec for
# pure-Ruby testing without Redis.
#
# Run: bundle exec rspec spec/unit/onetime/models/organization_membership/with_materialized_entitlements_spec.rb

require 'spec_helper'

require_relative '../../../../../lib/onetime/models/organization_membership/features/with_materialized_entitlements'

RSpec.describe 'MembershipMaterializedEntitlements', billing: true do

  # ---------------------------------------------------------------------------
  # Section 1: ROLE_ENTITLEMENTS Constant Structure
  # ---------------------------------------------------------------------------

  describe 'ROLE_ENTITLEMENTS constant' do
    subject(:role_entitlements) { Onetime::OrganizationMembership::ROLE_ENTITLEMENTS }

    it 'is defined on OrganizationMembership' do
      expect(Onetime::OrganizationMembership.const_defined?(:ROLE_ENTITLEMENTS)).to be true
    end

    it 'has entries for owner, admin, member' do
      expect(role_entitlements.keys.sort).to eq(%w[admin member owner])
    end

    describe 'role hierarchy' do
      let(:owner) { role_entitlements['owner'] }
      let(:admin) { role_entitlements['admin'] }
      let(:member) { role_entitlements['member'] }

      it 'owner template includes all admin entitlements' do
        expect((admin - owner)).to be_empty
      end

      it 'owner template includes all member entitlements' do
        expect((member - owner)).to be_empty
      end

      it 'admin template includes all member entitlements' do
        expect((member - admin)).to be_empty
      end

      it 'member entitlements do NOT include admin-only entitlements' do
        expect((admin - member)).not_to be_empty
      end
    end

    describe 'role-specific entitlements' do
      let(:owner) { role_entitlements['owner'] }
      let(:admin) { role_entitlements['admin'] }
      let(:member) { role_entitlements['member'] }

      it 'owner-only includes manage_billing (not in admin)' do
        expect(owner).to include('manage_billing')
        expect(admin).not_to include('manage_billing')
      end

      it 'owner-only includes manage_orgs (not in admin)' do
        expect(owner).to include('manage_orgs')
        expect(admin).not_to include('manage_orgs')
      end

      it 'admin-only includes manage_members (not in member)' do
        expect(admin).to include('manage_members')
        expect(member).not_to include('manage_members')
      end

      it 'admin-only includes audit_logs (not in member)' do
        expect(admin).to include('audit_logs')
        expect(member).not_to include('audit_logs')
      end

      it 'member entitlements include create_secrets' do
        expect(member).to include('create_secrets')
      end

      it 'member entitlements include api_access' do
        expect(member).to include('api_access')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Test doubles for pure-Ruby testing (same pattern as org-level spec)
  # ---------------------------------------------------------------------------

  class FakeSet
    def initialize = @data = Set.new
    def add(v)    = @data.add(v.to_s)
    def delete(v) = @data.delete(v.to_s)
    alias remove_element delete
    def each(&b)  = @data.each(&b)
    def clear     = @data.clear
    def to_a      = @data.to_a
    def to_set    = @data.dup
    def size      = @data.size
    def include?(v) = @data.include?(v.to_s)
  end

  let(:test_class) do
    feature_mod = Onetime::Models::Features::MembershipMaterializedEntitlements

    Class.new do
      include feature_mod::InstanceMethods
      extend  feature_mod::ClassMethods

      attr_accessor :materialized_entitlements_at
      attr_accessor :role
      attr_accessor :org_entitlements # simulates org.materialized_entitlements

      def initialize
        @entitlements_plan         = FakeSet.new
        @entitlements_grants       = FakeSet.new
        @entitlements_revokes      = FakeSet.new
        @materialized_entitlements = FakeSet.new
        @materialized_entitlements_at = nil
        @role = 'member'
        @org_entitlements = FakeSet.new
      end

      def entitlements_plan         = @entitlements_plan
      def entitlements_grants       = @entitlements_grants
      def entitlements_revokes      = @entitlements_revokes
      def materialized_entitlements = @materialized_entitlements

      # Stub organization to return a fake org with materialized_entitlements
      def organization
        org_ents = @org_entitlements
        Class.new do
          define_method(:materialized_entitlements) { org_ents }
        end.new
      end

      def save_with_collections(update_expiration: true)
        yield if block_given?
        true
      end

      def transaction
        yield if block_given?
      end
    end
  end

  let(:membership) { test_class.new }

  # ---------------------------------------------------------------------------
  # Section 2: Interface compliance
  # ---------------------------------------------------------------------------

  describe 'instance methods' do
    it 'responds to entitlements_materialized?' do
      expect(membership).to respond_to(:entitlements_materialized?)
    end

    it 'responds to materialize_for_role!' do
      expect(membership).to respond_to(:materialize_for_role!)
    end

    it 'responds to can?' do
      expect(membership).to respond_to(:can?)
    end

    it 'responds to grant_entitlement' do
      expect(membership).to respond_to(:grant_entitlement)
    end

    it 'responds to revoke_entitlement' do
      expect(membership).to respond_to(:revoke_entitlement)
    end
  end

  # ---------------------------------------------------------------------------
  # Section 3: materialize_for_role!
  # ---------------------------------------------------------------------------

  describe '#materialize_for_role!' do
    before do
      # Simulate org with full plan entitlements
      %w[create_secrets view_receipt api_access manage_members audit_logs manage_billing manage_orgs].each do |ent|
        membership.org_entitlements.add(ent)
      end
    end

    it 'materializes entitlements for owner role' do
      membership.role = 'owner'
      membership.materialize_for_role!

      expect(membership.materialized_entitlements.to_a).to include('manage_billing')
      expect(membership.materialized_entitlements.to_a).to include('create_secrets')
    end

    it 'materializes entitlements for admin role (no manage_billing)' do
      membership.role = 'admin'
      membership.materialize_for_role!

      expect(membership.materialized_entitlements.to_a).to include('manage_members')
      expect(membership.materialized_entitlements.to_a).not_to include('manage_billing')
    end

    it 'materializes entitlements for member role (no admin entitlements)' do
      membership.role = 'member'
      membership.materialize_for_role!

      expect(membership.materialized_entitlements.to_a).to include('create_secrets')
      expect(membership.materialized_entitlements.to_a).not_to include('manage_members')
      expect(membership.materialized_entitlements.to_a).not_to include('manage_billing')
    end

    it 'sets entitlements_materialized? to true after materialization' do
      membership.materialize_for_role!

      expect(membership.entitlements_materialized?).to be true
    end

    it 'stamps materialized_entitlements_at with timestamp:hash format' do
      membership.materialize_for_role!

      stamp = membership.materialized_entitlements_at.to_s
      expect(stamp).to match(/\A\d+:[0-9a-f]{12}\z/)
    end

    it 'intersects with org entitlements (org missing entitlement = member lacks it)' do
      # Clear org entitlements and only add create_secrets
      membership.org_entitlements.clear
      membership.org_entitlements.add('create_secrets')
      membership.role = 'owner'

      membership.materialize_for_role!

      # Even owner can't have entitlements the org doesn't have
      expect(membership.materialized_entitlements.to_a).to eq(['create_secrets'])
      expect(membership.materialized_entitlements.to_a).not_to include('manage_billing')
    end

    context 'when pre-loaded org is passed' do
      let(:preloaded_org) do
        ents = FakeSet.new
        %w[create_secrets api_access manage_billing].each { |e| ents.add(e) }
        Class.new do
          define_method(:materialized_entitlements) { ents }
        end.new
      end

      it 'uses the passed org instead of calling organization' do
        membership.role = 'owner'
        # Spy on organization to verify it's not called
        organization_called = false
        allow(membership).to receive(:organization) do
          organization_called = true
          nil # Return nil to fail fast if it were called
        end

        membership.materialize_for_role!(preloaded_org)

        expect(organization_called).to be false
        expect(membership.materialized_entitlements.to_a).to include('manage_billing')
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Section 4: can?() method
  # ---------------------------------------------------------------------------

  describe '#can?' do
    before do
      membership.entitlements_plan.add('create_secrets')
      membership.entitlements_plan.add('api_access')
      membership.apply_entitlements
      # Mark as materialized so can? reads from materialized_entitlements
      membership.materialized_entitlements_at = "#{Time.now.to_i}:abc123def456"
    end

    it 'returns true for entitlement in materialized set' do
      expect(membership.can?('create_secrets')).to be true
    end

    it 'returns false for entitlement not in materialized set' do
      expect(membership.can?('manage_billing')).to be false
    end

    it 'accepts symbol argument (coerced to string)' do
      expect(membership.can?(:create_secrets)).to be true
    end

    it 'returns false for unknown entitlement' do
      expect(membership.can?('nonexistent_entitlement')).to be false
    end
  end

  # ---------------------------------------------------------------------------
  # Section 5: Operator grants/revokes
  # ---------------------------------------------------------------------------

  describe '#grant_entitlement' do
    before do
      membership.entitlements_plan.add('create_secrets')
      membership.apply_entitlements
      # Mark as materialized so can? reads from materialized_entitlements
      membership.materialized_entitlements_at = "#{Time.now.to_i}:abc123def456"
    end

    it 'adds entitlement to grants set' do
      membership.grant_entitlement('manage_members')

      expect(membership.entitlements_grants.include?('manage_members')).to be true
    end

    it 'makes entitlement available via can?' do
      membership.grant_entitlement('manage_members')

      expect(membership.can?('manage_members')).to be true
    end

    it 'removes entitlement from revokes if previously revoked' do
      membership.entitlements_revokes.add('manage_members')
      membership.grant_entitlement('manage_members')

      expect(membership.entitlements_revokes.include?('manage_members')).to be false
    end

    it 'accepts symbol and coerces to string' do
      membership.grant_entitlement(:manage_members)

      expect(membership.entitlements_grants.include?('manage_members')).to be true
    end
  end

  describe '#revoke_entitlement' do
    before do
      membership.entitlements_plan.add('create_secrets')
      membership.entitlements_plan.add('api_access')
      membership.apply_entitlements
    end

    it 'adds entitlement to revokes set' do
      membership.revoke_entitlement('api_access')

      expect(membership.entitlements_revokes.include?('api_access')).to be true
    end

    it 'removes entitlement from materialized_entitlements' do
      membership.revoke_entitlement('api_access')

      expect(membership.can?('api_access')).to be false
    end

    it 'removes entitlement from grants if previously granted' do
      membership.entitlements_grants.add('api_access')
      membership.revoke_entitlement('api_access')

      expect(membership.entitlements_grants.include?('api_access')).to be false
    end

    it 'accepts symbol and coerces to string' do
      membership.revoke_entitlement(:api_access)

      expect(membership.entitlements_revokes.include?('api_access')).to be true
    end
  end

  describe 'grant persistence in entitlements_grants' do
    before do
      membership.entitlements_plan.add('create_secrets')
      membership.apply_entitlements
    end

    it 'persists grant in entitlements_grants set' do
      membership.grant_entitlement('audit_logs')

      expect(membership.entitlements_grants.include?('audit_logs')).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Section 6: Role label unchanged after grant
  # ---------------------------------------------------------------------------

  describe 'role label after grant' do
    it 'role remains unchanged after granting admin-level entitlement to member' do
      membership.role = 'member'
      membership.grant_entitlement('manage_members')

      expect(membership.role).to eq('member')
    end
  end

  # ---------------------------------------------------------------------------
  # Section 7: clear_entitlement_overrides
  # ---------------------------------------------------------------------------

  describe '#clear_entitlement_overrides' do
    before do
      membership.entitlements_plan.add('create_secrets')
      membership.entitlements_grants.add('manage_members')
      membership.entitlements_revokes.add('create_secrets')
      membership.apply_entitlements
    end

    it 'clears grants set' do
      membership.clear_entitlement_overrides

      expect(membership.entitlements_grants.to_a).to be_empty
    end

    it 'clears revokes set' do
      membership.clear_entitlement_overrides

      expect(membership.entitlements_revokes.to_a).to be_empty
    end

    it 'returns plan-only entitlements after clearing' do
      result = membership.clear_entitlement_overrides

      expect(result).to contain_exactly('create_secrets')
    end
  end

  # ---------------------------------------------------------------------------
  # Section 8: apply_entitlements reconciliation
  # ---------------------------------------------------------------------------

  describe '#apply_entitlements' do
    it 'plan only -> materialized equals plan' do
      membership.entitlements_plan.add('create_secrets')
      membership.entitlements_plan.add('api_access')

      result = membership.apply_entitlements

      expect(result).to contain_exactly('create_secrets', 'api_access')
    end

    it 'plan + grants -> union of both' do
      membership.entitlements_plan.add('create_secrets')
      membership.entitlements_grants.add('manage_members')

      membership.apply_entitlements

      expect(membership.materialized_entitlements.to_a).to contain_exactly('create_secrets', 'manage_members')
    end

    it 'plan - revokes -> plan minus revoked item' do
      membership.entitlements_plan.add('create_secrets')
      membership.entitlements_plan.add('api_access')
      membership.entitlements_revokes.add('api_access')

      membership.apply_entitlements

      expect(membership.materialized_entitlements.to_a).to contain_exactly('create_secrets')
    end

    it 'plan + grants - revokes in correct order' do
      membership.entitlements_plan.add('create_secrets')
      membership.entitlements_grants.add('manage_members')
      membership.entitlements_revokes.add('create_secrets')

      membership.apply_entitlements

      expect(membership.materialized_entitlements.to_a).to contain_exactly('manage_members')
    end

    it 'idempotent: calling twice produces the same result' do
      membership.entitlements_plan.add('create_secrets')
      membership.entitlements_grants.add('manage_members')
      membership.entitlements_revokes.add('create_secrets')

      membership.apply_entitlements
      first_result = membership.materialized_entitlements.to_a.sort

      membership.apply_entitlements
      second_result = membership.materialized_entitlements.to_a.sort

      expect(second_result).to eq(first_result)
    end
  end

  # ---------------------------------------------------------------------------
  # Section 9: entitlements_materialized? and staleness
  # ---------------------------------------------------------------------------

  describe '#entitlements_materialized?' do
    it 'returns false when materialized_entitlements_at is nil' do
      membership.materialized_entitlements_at = nil

      expect(membership.entitlements_materialized?).to be false
    end

    it 'returns false when materialized_entitlements_at is empty string' do
      membership.materialized_entitlements_at = ''

      expect(membership.entitlements_materialized?).to be false
    end

    it 'returns true when materialized_entitlements_at is set' do
      membership.materialized_entitlements_at = '1716000000:abc123def456'

      expect(membership.entitlements_materialized?).to be true
    end
  end

  describe '#materialized_entitlements_at_parsed' do
    it 'returns nil when not set' do
      membership.materialized_entitlements_at = nil

      expect(membership.materialized_entitlements_at_parsed).to be_nil
    end

    it 'parses timestamp and content_hash from stamp' do
      membership.materialized_entitlements_at = '1716000000:abc123def456'
      result = membership.materialized_entitlements_at_parsed

      expect(result[:timestamp]).to eq(1716000000)
      expect(result[:content_hash]).to eq('abc123def456')
    end

    it 'returns nil for malformed stamp (no colon)' do
      membership.materialized_entitlements_at = 'badstamp'

      expect(membership.materialized_entitlements_at_parsed).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Section 10: Content hash determinism
  # ---------------------------------------------------------------------------

  describe '.entitlements_content_hash' do
    subject { test_class }

    it 'produces the same hash regardless of input order' do
      h1 = subject.entitlements_content_hash(%w[create_secrets api_access manage_members])
      h2 = subject.entitlements_content_hash(%w[manage_members create_secrets api_access])

      expect(h1).to eq(h2)
    end

    it 'produces different hashes for different entitlement sets' do
      h1 = subject.entitlements_content_hash(%w[create_secrets])
      h2 = subject.entitlements_content_hash(%w[create_secrets api_access])

      expect(h1).not_to eq(h2)
    end

    it 'returns a 12-character hex string' do
      hash = subject.entitlements_content_hash(%w[create_secrets])

      expect(hash).to match(/\A[0-9a-f]{12}\z/)
    end

    it 'returns a stable hash for empty array' do
      h = subject.entitlements_content_hash([])

      expect(h).to be_a(String)
      expect(h.length).to eq(12)
    end
  end
end

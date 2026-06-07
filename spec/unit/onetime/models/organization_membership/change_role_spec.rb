# spec/unit/onetime/models/organization_membership/change_role_spec.rb
#
# frozen_string_literal: true

# Unit tests for OrganizationMembership#change_role! method
#
# Verifies that role changes:
# - Trigger re-materialization of entitlements
# - Raise on invalid roles
# - Raise on materialization failure
#
# These tests use mocks to isolate the method under test.

require 'spec_helper'

RSpec.describe 'OrganizationMembership#change_role!' do
  let(:membership) do
    instance_double(
      Onetime::OrganizationMembership,
      role: 'member',
      organization_objid: 'org-123'
    ).tap do |m|
      # Allow the real change_role! behavior
      allow(m).to receive(:role=)
      allow(m).to receive(:materialize_for_role!).and_return(true)
    end
  end

  let(:org) do
    instance_double(
      Onetime::Organization,
      objid: 'org-123',
      entitlements: %w[create_secrets api_access manage_members manage_billing]
    )
  end

  describe 'contract verification' do
    it 'ROLE_ENTITLEMENTS constant is defined' do
      expect(Onetime::OrganizationMembership::ROLE_ENTITLEMENTS).to be_a(Hash)
    end

    it 'ROLE_ENTITLEMENTS has owner, admin, member keys' do
      expect(Onetime::OrganizationMembership::ROLE_ENTITLEMENTS.keys.sort).to eq(%w[admin member owner])
    end

    it 'OrganizationMembership responds to change_role!' do
      expect(Onetime::OrganizationMembership.instance_methods).to include(:change_role!)
    end
  end

  describe 'change_role! behavior via integration test' do
    # Use a real membership instance to test the actual method
    let(:real_membership) do
      m = Onetime::OrganizationMembership.new
      m.organization_objid = 'org-123'
      m.role = 'member'
      m
    end

    before do
      allow(Onetime::Organization).to receive(:load).with('org-123').and_return(org)
      # Persist the membership so its hash key exists before the stubbed
      # save_with_collections yields its collection writes. In production the
      # real save_with_collections saves the scalar fields first; the stub
      # skips that, so without this Familia v2.10's raise_on_unsaved_parent_write
      # guard would reject the entitlements_plan writes on a never-saved parent.
      real_membership.save
      # Stub save_with_collections to avoid a second Redis round-trip; yield so
      # the collection operations in materialize_for_role! still execute.
      allow(real_membership).to receive(:save_with_collections).and_yield.and_return(true)
    end

    context 'with valid role change' do
      it 'changes the role' do
        real_membership.change_role!('admin')

        expect(real_membership.role).to eq('admin')
      end

      it 'returns true on success' do
        result = real_membership.change_role!('admin')

        expect(result).to be true
      end
    end

    context 'with no-op (same role)' do
      it 'returns true without calling materialize_for_role!' do
        real_membership.role = 'member'
        expect(real_membership).not_to receive(:materialize_for_role!)

        result = real_membership.change_role!('member')

        expect(result).to be true
      end
    end

    context 'with invalid role' do
      it 'raises Onetime::Problem with descriptive message' do
        expect { real_membership.change_role!('superuser') }
          .to raise_error(Onetime::Problem, /Invalid role.*superuser/)
      end

      it 'lists valid roles in error message' do
        expect { real_membership.change_role!('superuser') }
          .to raise_error(Onetime::Problem, /owner.*admin.*member/)
      end

      it 'does not change the role' do
        original_role = real_membership.role
        expect { real_membership.change_role!('superuser') }.to raise_error(Onetime::Problem)

        expect(real_membership.role).to eq(original_role)
      end
    end

    context 'when materialization fails (org not found)' do
      before do
        allow(Onetime::Organization).to receive(:load).with('org-123').and_return(nil)
      end

      it 'raises Onetime::Problem about materialization failure' do
        expect { real_membership.change_role!('admin') }
          .to raise_error(Onetime::Problem, /Materialization failed/)
      end
    end
  end
end

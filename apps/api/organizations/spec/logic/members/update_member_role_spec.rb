# apps/api/organizations/spec/logic/members/update_member_role_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'organizations/logic'

RSpec.describe OrganizationAPI::Logic::Members::UpdateMemberRole do
  let(:owner) do
    instance_double(
      Onetime::Customer,
      objid: 'cust-owner-123',
      custid: 'cust-owner-123',
      extid: 'ext-cust-owner',
      email: 'owner@example.com',
      anonymous?: false,
      role: 'customer',
      'role?': false
    )
  end

  let(:target_member) do
    instance_double(
      Onetime::Customer,
      objid: 'cust-target-456',
      custid: 'cust-target-456',
      extid: 'ext-cust-target',
      email: 'member@example.com',
      anonymous?: false
    )
  end

  let(:organization) do
    instance_double(
      Onetime::Organization,
      objid: 'org-123',
      extid: 'ext-org-123',
      display_name: 'Test Organization'
    )
  end

  let(:target_membership) do
    instance_double(
      Onetime::OrganizationMembership,
      objid: 'membership-target-456',
      role: 'member',
      'role=': nil,
      'updated_at=': nil,
      active?: true,
      owner?: false,
      save: true
    )
  end

  let(:session) { { 'csrf' => 'test-csrf-token' } }

  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: owner,
      authenticated?: true,
      metadata: {}
    )
  end

  let(:params) do
    {
      'extid' => 'ext-org-123',
      'member_extid' => 'ext-cust-target',
      'role' => 'admin'
    }
  end

  subject(:logic) { described_class.new(strategy_result, params) }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(Familia).to receive(:now).and_return(Time.now.to_f)
  end

  describe '#process_params' do
    it 'extracts role from params and downcases it' do
      params['role'] = 'ADMIN'
      new_logic = described_class.new(strategy_result, params)
      expect(new_logic.new_role).to eq('admin')
    end

    it 'strips whitespace from role' do
      params['role'] = '  member  '
      new_logic = described_class.new(strategy_result, params)
      expect(new_logic.new_role).to eq('member')
    end
  end

  describe '#raise_concerns' do
    before do
      allow(Onetime::Organization).to receive(:find_by_extid)
        .with('ext-org-123').and_return(organization)
      allow(organization).to receive(:owner?).with(owner).and_return(true)
      allow(Onetime::Customer).to receive(:find_by_extid)
        .with('ext-cust-target').and_return(target_member)
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
        .with('org-123', 'cust-target-456').and_return(target_membership)
    end

    context 'when customer is anonymous' do
      let(:owner) do
        instance_double(
          Onetime::Customer,
          objid: 'anon-123',
          anonymous?: true
        )
      end

      it 'raises unauthorized error' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::FormError, /Authentication required/
        )
      end
    end

    context 'when organization not found' do
      before do
        allow(Onetime::Organization).to receive(:find_by_extid).and_return(nil)
      end

      it 'raises not found error' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::RecordNotFound, /Organization not found/
        )
      end
    end

    context 'when user is not owner' do
      before do
        allow(organization).to receive(:owner?).with(owner).and_return(false)
      end

      it 'raises forbidden error' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::Forbidden, /Only organization owner/
        )
      end
    end

    context 'when member not found' do
      before do
        allow(Onetime::Customer).to receive(:find_by_extid).and_return(nil)
      end

      it 'raises not found error' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::RecordNotFound, /Member not found/
        )
      end
    end

    context 'when membership not found' do
      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
          .and_return(nil)
      end

      it 'raises not found error' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::RecordNotFound, /Member not found in this organization/
        )
      end
    end

    context 'when membership is not active' do
      before do
        allow(target_membership).to receive(:active?).and_return(false)
      end

      it 'raises form error' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::FormError, /not active/
        )
      end
    end

    context 'when role is invalid' do
      let(:params) do
        {
          'extid' => 'ext-org-123',
          'member_extid' => 'ext-cust-target',
          'role' => 'superuser'
        }
      end

      it 'raises form error for invalid role' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::FormError, /Invalid role/
        )
      end
    end

    context 'when trying to change owner role' do
      before do
        allow(target_membership).to receive(:owner?).and_return(true)
      end

      it 'raises form error' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::FormError, /Cannot change owner role/
        )
      end
    end

    context 'when member already has the role' do
      before do
        allow(target_membership).to receive(:role).and_return('admin')
      end

      it 'raises form error' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::FormError, /already has role/
        )
      end
    end

    context 'when trying to set role to owner' do
      let(:params) do
        {
          'extid' => 'ext-org-123',
          'member_extid' => 'ext-cust-target',
          'role' => 'owner'
        }
      end

      it 'raises form error for invalid role' do
        # 'owner' is not in VALID_ROLES, so it fails validation first
        expect { logic.raise_concerns }.to raise_error(
          Onetime::FormError, /Invalid role/
        )
      end
    end

    context 'with valid params and owner permission' do
      it 'does not raise any error' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end
  end

  describe '#process' do
    # Use a real-ish object to track role changes
    let(:current_role) { 'member' }

    before do
      allow(Onetime::Organization).to receive(:find_by_extid).and_return(organization)
      allow(organization).to receive(:owner?).with(owner).and_return(true)
      allow(Onetime::Customer).to receive(:find_by_extid).and_return(target_member)
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
        .and_return(target_membership)

      # Setup mutable role tracking - initially returns 'member'
      role_value = current_role
      allow(target_membership).to receive(:role) { role_value }
      allow(target_membership).to receive(:role=) { |new_val| role_value = new_val }
      allow(target_membership).to receive(:updated_at=)

      logic.raise_concerns
    end

    it 'updates membership role' do
      expect(target_membership).to receive(:role=).with('admin')
      expect(target_membership).to receive(:save)
      logic.process
    end

    it 'updates membership timestamp' do
      expect(target_membership).to receive(:updated_at=)
      logic.process
    end

    it 'returns success data with role change' do
      result = logic.process
      expect(result).to have_key(:user_id)
      expect(result).to have_key(:organization_id)
      expect(result).to have_key(:record)
      expect(result[:user_id]).to eq('cust-owner-123')
      expect(result[:organization_id]).to eq('ext-org-123')
    end

    it 'includes previous_role in response' do
      result = logic.process
      expect(result[:record]).to have_key(:previous_role)
      expect(result[:record][:previous_role]).to eq('member')
    end

    it 'includes new role in response' do
      result = logic.process
      # Role should be updated to 'admin' after the save
      expect(result[:record][:role]).to eq('admin')
    end

    it 'logs audit event with role change details' do
      expect(OT).to receive(:info).with(/\[AUDIT\].*role_change.*old_role=member.*new_role=admin/)
      logic.process
    end

    it 'captures old_role before updating' do
      # Verify that @old_role is captured before the role is changed
      result = logic.process
      expect(result[:record][:previous_role]).to eq('member')
      expect(result[:record][:role]).to eq('admin')
    end
  end

  describe '#success_data' do
    before do
      allow(Onetime::Organization).to receive(:find_by_extid).and_return(organization)
      allow(organization).to receive(:owner?).with(owner).and_return(true)
      allow(Onetime::Customer).to receive(:find_by_extid).and_return(target_member)
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
        .and_return(target_membership)

      # Setup mutable role tracking
      role_value = 'member'
      allow(target_membership).to receive(:role) { role_value }
      allow(target_membership).to receive(:role=) { |new_val| role_value = new_val }
      allow(target_membership).to receive(:updated_at=)

      logic.raise_concerns
      logic.process
    end

    it 'returns hash with expected keys' do
      # Access via instance variable after process is called
      result = logic.send(:success_data)
      expect(result.keys).to include(:user_id, :organization_id, :record)
    end

    it 'includes member id in record' do
      result = logic.send(:success_data)
      expect(result[:record][:id]).to eq('ext-cust-target')
    end

    it 'includes member email in record' do
      result = logic.send(:success_data)
      expect(result[:record][:email]).to eq('member@example.com')
    end
  end

  describe '#form_fields' do
    it 'returns hash with role' do
      fields = logic.form_fields
      expect(fields[:role]).to eq('admin')
    end
  end
end

# apps/api/organizations/spec/logic/invitations/create_invitation_spec.rb
#
# frozen_string_literal: true

require_relative File.join(Onetime::HOME, 'spec', 'spec_helper')
require 'organizations/logic'

RSpec.describe OrganizationAPI::Logic::Invitations::CreateInvitation do
  let(:customer) do
    instance_double(
      Onetime::Customer,
      objid: 'cust-owner-123',
      custid: 'cust-owner-123',
      extid: 'ext-cust-owner',
      email: 'owner@example.com',
      anonymous?: false,
      role: 'customer'
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

  let(:session) { { 'csrf' => 'test-csrf-token' } }

  let(:strategy_result) do
    double('StrategyResult',
      session: session,
      user: customer,
      authenticated?: true,
      metadata: {}
    )
  end

  let(:params) do
    {
      'extid' => 'ext-org-123',
      'email' => 'invitee@example.com',
      'role' => 'member'
    }
  end

  subject(:logic) { described_class.new(strategy_result, params) }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:li)
    allow(OT::Utils).to receive(:obscure_email).and_return('inv***@example.com')
  end

  describe '#process_params' do
    it 'extracts email from params and downcases it' do
      params['email'] = 'UPPER@EXAMPLE.COM'
      new_logic = described_class.new(strategy_result, params)
      expect(new_logic.email).to eq('upper@example.com')
    end

    it 'extracts role from params' do
      expect(logic.role).to eq('member')
    end

    it 'defaults role to member when empty' do
      params['role'] = ''
      new_logic = described_class.new(strategy_result, params)
      expect(new_logic.role).to eq('member')
    end

    it 'strips whitespace from email' do
      params['email'] = '  spaced@example.com  '
      new_logic = described_class.new(strategy_result, params)
      expect(new_logic.email).to eq('spaced@example.com')
    end
  end

  describe '#raise_concerns' do
    before do
      allow(Onetime::Organization).to receive(:find_by_extid)
        .with('ext-org-123').and_return(organization)
      allow(organization).to receive(:owner?).with(customer).and_return(true)
      allow(Onetime::Customer).to receive(:find_by_email).and_return(nil)
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_email).and_return(nil)
    end

    context 'when customer is anonymous' do
      let(:customer) do
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

    context 'when user is not owner or admin' do
      before do
        allow(organization).to receive(:owner?).with(customer).and_return(false)
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
          .and_return(nil)
      end

      it 'raises authorization error' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::Forbidden, /Only organization owners and admins/
        )
      end
    end

    context 'when email is empty' do
      let(:params) { { 'extid' => 'ext-org-123', 'email' => '', 'role' => 'member' } }

      it 'raises form error for missing email' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::FormError, /Email is required/
        )
      end
    end

    context 'when email format is invalid' do
      let(:params) { { 'extid' => 'ext-org-123', 'email' => 'not-an-email', 'role' => 'member' } }

      it 'raises form error for invalid email' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::FormError, /Invalid email format/
        )
      end
    end

    context 'when role is invalid' do
      let(:params) { { 'extid' => 'ext-org-123', 'email' => 'test@example.com', 'role' => 'superuser' } }

      it 'raises form error for invalid role' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::FormError, /Role must be member or admin/
        )
      end
    end

    context 'when role is owner' do
      let(:params) { { 'extid' => 'ext-org-123', 'email' => 'test@example.com', 'role' => 'owner' } }

      # Note: 'owner' is not in the allowed list ['member', 'admin'],
      # so role validation fires before the explicit "Cannot invite as owner" check
      it 'raises form error for invalid role' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::FormError, /Role must be member or admin/
        )
      end
    end

    context 'when user is already a member' do
      let(:existing_customer) do
        instance_double(Onetime::Customer, objid: 'existing-cust')
      end

      before do
        allow(Onetime::Customer).to receive(:find_by_email)
          .with('invitee@example.com').and_return(existing_customer)
        allow(organization).to receive(:member?).with(existing_customer).and_return(true)
      end

      it 'raises form error for existing member' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::FormError, /already a member/
        )
      end
    end

    context 'when invitation is already pending' do
      let(:pending_invite) do
        instance_double(Onetime::OrganizationMembership, pending?: true)
      end

      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_email)
          .and_return(pending_invite)
      end

      it 'raises form error for duplicate invitation' do
        expect { logic.raise_concerns }.to raise_error(
          Onetime::FormError, /Invitation already pending/
        )
      end
    end

    context 'when admin role is specified' do
      let(:params) { { 'extid' => 'ext-org-123', 'email' => 'admin@example.com', 'role' => 'admin' } }

      it 'allows admin role' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end

    context 'with valid params and owner permission' do
      it 'does not raise any error' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end

    context 'with valid params and admin permission' do
      let(:admin_membership) do
        instance_double(Onetime::OrganizationMembership, admin?: true)
      end

      before do
        allow(organization).to receive(:owner?).with(customer).and_return(false)
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
          .with('org-123', 'cust-owner-123').and_return(admin_membership)
      end

      it 'allows admin to create invitation' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end
  end

  describe '#process' do
    let(:new_membership) do
      instance_double(
        Onetime::OrganizationMembership,
        objid: 'membership-new-123',
        token: 'invite-token-abc',
        safe_dump: { 'id' => 'membership-new-123', 'role' => 'member', 'status' => 'pending' }
      )
    end

    before do
      allow(Onetime::Organization).to receive(:find_by_extid).and_return(organization)
      allow(organization).to receive(:owner?).with(customer).and_return(true)
      allow(Onetime::Customer).to receive(:find_by_email).and_return(nil)
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_email).and_return(nil)
      allow(Onetime::OrganizationMembership).to receive(:create_invitation!)
        .and_return(new_membership)
      allow(Onetime::Jobs::Publisher).to receive(:enqueue_email)

      # Call raise_concerns to set up @organization
      logic.raise_concerns
    end

    it 'creates invitation membership' do
      expect(Onetime::OrganizationMembership).to receive(:create_invitation!)
        .with(
          organization: organization,
          email: 'invitee@example.com',
          role: 'member',
          inviter: customer
        )
        .and_return(new_membership)
      logic.process
    end

    it 'queues invitation email' do
      expect(Onetime::Jobs::Publisher).to receive(:enqueue_email)
        .with(
          :organization_invitation,
          hash_including(
            invited_email: 'invitee@example.com',
            organization_name: 'Test Organization',
            inviter_email: 'owner@example.com',
            role: 'member',
            invite_token: 'invite-token-abc'
          ),
          fallback: :sync
        )
      logic.process
    end

    it 'returns success data with membership record' do
      result = logic.process
      expect(result).to have_key(:user_id)
      expect(result).to have_key(:record)
      expect(result[:user_id]).to eq('cust-owner-123')
      expect(result[:record]).to include('id' => 'membership-new-123')
    end

    it 'logs the invitation creation' do
      expect(OT).to receive(:info).with(/Created invitation/)
      logic.process
    end
  end

  describe '#form_fields' do
    it 'returns hash with email and role' do
      fields = logic.form_fields
      expect(fields[:email]).to eq('invitee@example.com')
      expect(fields[:role]).to eq('member')
    end
  end

  describe '#valid_email?' do
    it 'validates correct email format' do
      expect(logic.send(:valid_email?, 'test@example.com')).to be_truthy
    end

    it 'validates email with subdomain' do
      expect(logic.send(:valid_email?, 'test@sub.example.com')).to be_truthy
    end

    it 'rejects email without @' do
      expect(logic.send(:valid_email?, 'notanemail')).to be_falsey
    end

    it 'rejects email without domain' do
      expect(logic.send(:valid_email?, 'test@')).to be_falsey
    end

    it 'rejects email with spaces' do
      expect(logic.send(:valid_email?, 'test @example.com')).to be_falsey
    end
  end

  describe '#check_member_quota!' do
    let(:entitlements) { double('SortedSet', any?: has_entitlements) }
    let(:has_entitlements) { false }

    before do
      allow(Onetime::Organization).to receive(:find_by_extid)
        .with('ext-org-123').and_return(organization)
      allow(organization).to receive(:owner?).with(customer).and_return(true)
      allow(organization).to receive(:respond_to?).with(:at_limit?).and_return(true)
      allow(organization).to receive(:entitlements).and_return(entitlements)
      allow(organization).to receive(:member_count).and_return(5)
      allow(organization).to receive(:pending_invitation_count).and_return(2)
      allow(Onetime::Customer).to receive(:find_by_email).and_return(nil)
      allow(Onetime::OrganizationMembership).to receive(:find_by_org_email).and_return(nil)
    end

    context 'when billing is disabled (no entitlements)' do
      let(:has_entitlements) { false }

      it 'skips quota check (standalone mode)' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end

    context 'when billing is enabled and at limit', billing: true do
      let(:has_entitlements) { true }

      before do
        # Current count: 5 members + 2 pending = 7 total
        allow(organization).to receive(:at_limit?)
          .with('members_per_team', 7).and_return(true)
      end

      it 'raises upgrade_required error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError) do |error|
          expect(error.message).to match(/Member limit reached/)
          expect(error.instance_variable_get(:@error_type)).to eq(:upgrade_required)
          expect(error.instance_variable_get(:@field)).to eq('email')
        end
      end
    end

    # Validation ordering: input errors before quota errors (#2256)
    context 'when at limit with invalid email', billing: true do
      let(:has_entitlements) { true }
      let(:params) { { 'extid' => 'ext-org-123', 'email' => 'not-valid', 'role' => 'member' } }

      before do
        allow(organization).to receive(:at_limit?)
          .with('members_per_team', 7).and_return(true)
      end

      it 'returns email validation error before quota error' do
        # User should see "invalid email" not "upgrade required"
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError) do |error|
          expect(error.message).to match(/Invalid email format/)
          expect(error.message).not_to match(/limit reached/)
        end
      end
    end

    context 'when billing is enabled and under limit', billing: true do
      let(:has_entitlements) { true }

      before do
        # Current count: 5 members + 2 pending = 7 total
        allow(organization).to receive(:at_limit?)
          .with('members_per_team', 7).and_return(false)
      end

      it 'allows invitation creation' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end
  end
end

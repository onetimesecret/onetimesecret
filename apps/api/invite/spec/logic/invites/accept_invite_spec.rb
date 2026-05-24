# apps/api/invite/spec/logic/invites/accept_invite_spec.rb
#
# frozen_string_literal: true

# AcceptInvite Endpoint Specification
#
# POST /api/invite/:token/accept
#
# This endpoint handles invitation acceptance for authenticated users.
# The user must be logged in and their email must match the invitation.
#
# Run: pnpm run test:rspec apps/api/invite/spec/logic/invites/accept_invite_spec.rb

require_relative '../../spec_helper'

RSpec.describe InviteAPI::Logic::Invites::AcceptInvite do
  let(:organization) do
    build_mock_organization(
      objid: 'org-test-123',
      extid: 'org-ext-test-123',
      display_name: 'Test Organization',
      'member?' => false
    )
  end

  let(:user_email) { 'user@example.com' }
  let(:normalized_email) { 'user@example.com' }
  let(:invite_token) { SecureRandom.hex(24) }

  let(:customer) do
    build_mock_customer(
      objid: 'cust-test-123',
      custid: 'cust-test-123',
      extid: 'ext-test-123',
      email: user_email,
      anonymous?: false
    )
  end

  let(:invitation) do
    inv = build_mock_invitation(
      objid: 'inv-test-123',
      token: invite_token,
      invited_email: user_email,
      role: 'member',
      organization: organization,
      organization_objid: 'org-test-123',
      'pending?' => true,
      'expired?' => false
    )
    allow(inv).to receive(:accept!).with(customer)
    allow(inv).to receive(:joined_at).and_return(Time.now.to_i)
    inv
  end

  let(:session) { { 'csrf' => 'test-csrf-token' } }

  let(:strategy_result) do
    build_strategy_result(
      session: session,
      user: customer,
      authenticated: true,
      metadata: {}
    )
  end

  let(:params) { { 'token' => invite_token } }

  subject(:logic) { described_class.new(strategy_result, params) }

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:le)
    allow(OT::Utils).to receive(:normalize_email) { |e| e.to_s.downcase.strip }
  end

  describe '#process_params' do
    it 'extracts and sanitizes token from params' do
      expect(logic.instance_variable_get(:@token)).to eq(invite_token)
    end
  end

  describe '#raise_concerns' do
    context 'when user is not authenticated' do
      let(:anon_customer) do
        build_mock_customer(
          anonymous?: true
        )
      end

      let(:unauthenticated_strategy) do
        build_strategy_result(
          session: session,
          user: anon_customer,
          authenticated: false,
          metadata: {}
        )
      end

      subject(:logic) { described_class.new(unauthenticated_strategy, params) }

      it 'raises authentication required error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Authentication required/i)
      end
    end

    context 'when token is missing' do
      let(:params) { { 'token' => '' } }

      it 'raises form error for missing token' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Token is required/)
      end
    end

    context 'when token is invalid/not found' do
      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_token)
          .with(invite_token)
          .and_return(nil)
      end

      it 'raises not found error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound)
      end
    end

    context 'when invitation is expired' do
      let(:expired_invitation) do
        build_mock_invitation(
          token: invite_token,
          invited_email: user_email,
          organization: organization,
          'pending?' => true,
          'expired?' => true
        )
      end

      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_token)
          .with(invite_token)
          .and_return(expired_invitation)
      end

      it 'raises form error for expired invitation' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /expired/i)
      end
    end

    context 'when invitation is already accepted' do
      let(:accepted_invitation) do
        build_mock_invitation(
          token: invite_token,
          invited_email: user_email,
          organization: organization,
          status: 'active',
          'pending?' => false,
          'active?' => true,
          'expired?' => false
        )
      end

      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_token)
          .with(invite_token)
          .and_return(accepted_invitation)
      end

      it 'raises form error for already accepted invitation' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /already been/)
      end
    end

    context 'when user email does not match invitation' do
      let(:different_email_customer) do
        build_mock_customer(
          email: 'different@example.com',
          anonymous?: false
        )
      end

      let(:strategy_with_different_user) do
        build_strategy_result(
          session: session,
          user: different_email_customer,
          authenticated: true,
          metadata: {}
        )
      end

      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_token)
          .with(invite_token)
          .and_return(invitation)
      end

      subject(:logic) { described_class.new(strategy_with_different_user, params) }

      it 'raises form error for email mismatch' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /does not match/i)
      end
    end

    context 'when user is already a member of the organization' do
      let(:org_with_existing_member) do
        build_mock_organization(
          objid: 'org-test-123',
          extid: 'org-ext-test-123',
          display_name: 'Test Organization'
        )
      end

      let(:invitation_to_org_user_is_member_of) do
        build_mock_invitation(
          token: invite_token,
          invited_email: user_email,
          organization: org_with_existing_member,
          'pending?' => true,
          'expired?' => false
        )
      end

      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_token)
          .with(invite_token)
          .and_return(invitation_to_org_user_is_member_of)
        allow(org_with_existing_member).to receive(:member?)
          .with(customer)
          .and_return(true)
      end

      it 'raises form error for existing membership' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /already a member/i)
      end
    end

    context 'with valid pending invitation' do
      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_token)
          .with(invite_token)
          .and_return(invitation)
        allow(organization).to receive(:member?)
          .with(customer)
          .and_return(false)
      end

      it 'does not raise any error' do
        expect { logic.raise_concerns }.not_to raise_error
      end
    end
  end

  describe '#process' do
    before do
      allow(Onetime::OrganizationMembership).to receive(:find_by_token)
        .with(invite_token)
        .and_return(invitation)
      allow(organization).to receive(:member?)
        .with(customer)
        .and_return(false)
    end

    context 'with valid request' do
      before do
        logic.raise_concerns
      end

      it 'accepts the invitation' do
        expect(invitation).to receive(:accept!).with(customer)
        logic.process
      end

      it 'logs the acceptance' do
        expect(OT).to receive(:info).with(
          '[AcceptInvite] User joined organization',
          hash_including(event: 'invite.accepted', result: :success)
        )
        logic.process
      end

      it 'returns success data' do
        result = logic.process
        expect(result).to include(:user_id)
        expect(result[:user_id]).to eq(customer.extid)
      end
    end
  end

  describe '#success_data' do
    before do
      allow(Onetime::OrganizationMembership).to receive(:find_by_token)
        .with(invite_token)
        .and_return(invitation)
      allow(organization).to receive(:member?)
        .with(customer)
        .and_return(false)
      logic.raise_concerns
    end

    it 'returns user_id as customer extid' do
      data = logic.success_data
      expect(data[:user_id]).to eq(customer.extid)
    end

    it 'returns organization details' do
      data = logic.success_data
      expect(data[:organization][:id]).to eq(organization.extid)
      expect(data[:organization][:display_name]).to eq('Test Organization')
    end

    it 'returns role from invitation' do
      data = logic.success_data
      expect(data[:role]).to eq('member')
    end

    it 'returns joined_at timestamp' do
      data = logic.success_data
      expect(data).to have_key(:joined_at)
    end
  end
end

# apps/api/invite/spec/logic/invites/signup_and_accept_spec.rb
#
# frozen_string_literal: true

# SignupAndAccept Endpoint Specification
#
# POST /api/invite/:token/signup
#
# This endpoint handles organization invite signups. It:
# - Validates invite token (must be pending, not expired)
# - Derives email from token (email not user-provided)
# - Checks if account already exists in authdb or Redis
# - Creates account + customer + default workspace
# - Accepts the invitation (adds user to organization)
# - Auto-logins the user
# - Returns success
#
# Run: pnpm run test:rspec apps/api/invite/spec/logic/invites/signup_and_accept_spec.rb

require_relative '../../spec_helper'

RSpec.describe InviteAPI::Logic::Invites::SignupAndAccept do
  let(:organization) do
    build_mock_organization(
      objid: 'org-test-123',
      extid: 'org-ext-test-123',
      display_name: 'Test Organization'
    )
  end

  let(:invited_email) { 'newuser@example.com' }
  let(:normalized_email) { 'newuser@example.com' }
  let(:invite_token) { SecureRandom.hex(24) }

  let(:invitation) do
    inv = build_mock_invitation(
      objid: 'inv-test-123',
      token: invite_token,
      invited_email: invited_email,
      role: 'member',
      organization: organization,
      organization_objid: 'org-test-123',
      'pending?' => true,
      'expired?' => false
    )
    allow(inv).to receive(:joined_at).and_return(Time.now.to_i)
    inv
  end

  let(:valid_password) { 'SecureP@ssw0rd123!' }
  let(:weak_password) { '123' }

  let(:session) { {} }
  let(:client_ip) { '192.168.1.100' }

  let(:strategy_result) do
    build_strategy_result(
      session: session,
      user: nil,          # Not authenticated - this is signup
      authenticated: false,
      metadata: { ip: client_ip }
    )
  end

  let(:valid_params) do
    {
      'token' => invite_token,
      'password' => valid_password
    }
  end

  let(:mock_auth_db) do
    # Mock Sequel dataset for accounts table
    accounts_ds = double('accounts_dataset')
    allow(accounts_ds).to receive(:where).and_return(accounts_ds)
    allow(accounts_ds).to receive(:any?).and_return(false)
    allow(accounts_ds).to receive(:first).and_return({ id: 123, email: normalized_email })
    allow(accounts_ds).to receive(:update)

    db = double('Auth::Database.connection')
    allow(db).to receive(:[]).with(:accounts).and_return(accounts_ds)
    db
  end

  # Source uses auth_logger (Onetime.get_logger('Auth')) for its semantic logs,
  # not the OT.info shim. Stub the Auth logger so .debug/.info/.error during
  # the spec don't fail the test, and so individual examples can set focused
  # expectations on it.
  let(:auth_logger_double) do
    instance_double(SemanticLogger::Logger, info: nil, debug: nil, warn: nil, error: nil)
  end

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:le)
    allow(OT::Utils).to receive(:normalize_email).and_return(normalized_email)
    allow(OT::Utils).to receive(:obscure_email).and_return('ne***@example.com')
    allow(Auth::Database).to receive(:connection).and_return(mock_auth_db)
    allow(Onetime).to receive(:get_logger).with('Auth').and_return(auth_logger_double)
  end

  describe '#process_params' do
    subject(:logic) { described_class.new(strategy_result, valid_params) }

    it 'extracts and sanitizes token from params' do
      expect(logic.instance_variable_get(:@token)).to eq(invite_token)
    end

    it 'extracts password from params' do
      expect(logic.instance_variable_get(:@password)).to eq(valid_password)
    end
  end

  describe '#raise_concerns' do
    let(:rate_limiter) { instance_double(Onetime::Security::InviteTokenRateLimiter) }

    before do
      allow(Onetime::Security::InviteTokenRateLimiter).to receive(:new)
        .with(client_ip)
        .and_return(rate_limiter)
      allow(rate_limiter).to receive(:check!)
      allow(rate_limiter).to receive(:record_attempt)
    end

    context 'with valid pending invitation' do
      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_token)
          .with(invite_token)
          .and_return(invitation)
        allow(Onetime::Customer).to receive(:email_exists?)
          .with(normalized_email)
          .and_return(false)
      end

      subject(:logic) { described_class.new(strategy_result, valid_params) }

      it 'does not raise any error' do
        expect { logic.raise_concerns }.not_to raise_error
      end

      it 'derives email from invitation token, not from user input' do
        logic.raise_concerns
        expect(logic.instance_variable_get(:@email)).to eq(normalized_email)
      end
    end

    context 'when token is missing' do
      let(:params_without_token) { valid_params.merge('token' => '') }

      subject(:logic) { described_class.new(strategy_result, params_without_token) }

      it 'raises form error for missing token' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Token is required/)
      end
    end

    context 'when password is missing' do
      let(:params_without_password) { valid_params.merge('password' => '') }

      subject(:logic) { described_class.new(strategy_result, params_without_password) }

      it 'raises form error for missing password' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Password is required/)
      end
    end

    context 'when token is invalid/not found' do
      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_token)
          .with(invite_token)
          .and_return(nil)
      end

      subject(:logic) { described_class.new(strategy_result, valid_params) }

      it 'raises not found error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::RecordNotFound)
      end
    end

    context 'when invitation is expired' do
      let(:expired_invitation) do
        build_mock_invitation(
          token: invite_token,
          invited_email: invited_email,
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

      subject(:logic) { described_class.new(strategy_result, valid_params) }

      it 'raises form error for expired invitation' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /expired/i)
      end
    end

    context 'when invitation is already accepted' do
      let(:accepted_invitation) do
        build_mock_invitation(
          token: invite_token,
          invited_email: invited_email,
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

      subject(:logic) { described_class.new(strategy_result, valid_params) }

      it 'raises form error for already accepted invitation' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /already been/)
      end
    end

    context 'when organization no longer exists' do
      let(:orphaned_invitation) do
        build_mock_invitation(
          token: invite_token,
          invited_email: invited_email,
          organization: nil,
          'pending?' => true,
          'expired?' => false
        )
      end

      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_token)
          .with(invite_token)
          .and_return(orphaned_invitation)
      end

      subject(:logic) { described_class.new(strategy_result, valid_params) }

      it 'raises form error for missing organization' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /Organization no longer exists/)
      end
    end

    context 'when account already exists in authdb' do
      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_token)
          .with(invite_token)
          .and_return(invitation)

        # Simulate account exists in authdb
        accounts_ds = double('accounts_dataset')
        allow(accounts_ds).to receive(:where).and_return(accounts_ds)
        allow(accounts_ds).to receive(:any?).and_return(true)
        allow(mock_auth_db).to receive(:[]).with(:accounts).and_return(accounts_ds)
      end

      subject(:logic) { described_class.new(strategy_result, valid_params) }

      it 'raises form error indicating account exists' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /already exists/i)
      end
    end

    context 'when account already exists in Redis (Customer)' do
      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_token)
          .with(invite_token)
          .and_return(invitation)
        allow(Onetime::Customer).to receive(:email_exists?)
          .with(normalized_email)
          .and_return(true)
      end

      subject(:logic) { described_class.new(strategy_result, valid_params) }

      it 'raises form error indicating account exists' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /already exists/i)
      end
    end

    context 'when password does not meet minimum length' do
      let(:params_with_weak_password) { valid_params.merge('password' => weak_password) }

      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_token)
          .with(invite_token)
          .and_return(invitation)
        allow(Onetime::Customer).to receive(:email_exists?)
          .with(normalized_email)
          .and_return(false)
      end

      subject(:logic) { described_class.new(strategy_result, params_with_weak_password) }

      it 'raises form error for weak password' do
        expect { logic.raise_concerns }.to raise_error(Onetime::FormError, /at least 8 characters/i)
      end
    end

    context 'when rate limited' do
      before do
        allow(rate_limiter).to receive(:check!)
          .and_raise(Onetime::LimitExceeded.new('Too many requests'))
      end

      subject(:logic) { described_class.new(strategy_result, valid_params) }

      it 'raises rate limit error' do
        expect { logic.raise_concerns }.to raise_error(Onetime::LimitExceeded)
      end
    end
  end

  # NOTE: The historical "#process" describe block tested an obsolete contract
  # where this logic class directly invoked Auth::Operations::CreateCustomer /
  # CreateDefaultWorkspace / AcceptInvitation. The current source (#3221)
  # delegates Customer/workspace creation to Rodauth's after_create_account
  # hook (apps/web/auth/config/hooks/account.rb) and reserves invitation
  # acceptance for a separate explicit /accept call. The current contract is
  # covered by "#process invitation reload after signup" below; see also the
  # success_data block.

  describe '#success_data' do
    let(:new_customer) do
      build_mock_customer(
        extid: 'ext-123',
        email: invited_email
      )
    end

    subject(:logic) { described_class.new(strategy_result, valid_params) }

    before do
      logic.instance_variable_set(:@customer, new_customer)
      logic.instance_variable_set(:@invitation, invitation)
    end

    it 'returns record wrapper with user_id' do
      data = logic.success_data
      expect(data[:record][:user_id]).to eq('ext-123')
    end

    it 'returns organization details' do
      data = logic.success_data
      expect(data[:record][:organization][:id]).to eq(organization.extid)
      expect(data[:record][:organization][:display_name]).to eq('Test Organization')
    end

    it 'returns role from invitation' do
      data = logic.success_data
      expect(data[:record][:role]).to eq('member')
    end

    it 'returns the invitation status (pending until the explicit /accept call)' do
      allow(invitation).to receive(:status).and_return('pending')
      data = logic.success_data
      expect(data[:record][:invitation_status]).to eq('pending')
    end

    it 'includes auto_login flag' do
      data = logic.success_data
      expect(data[:record][:auto_login]).to be true
    end
  end

  # GH #3221 — the after_create_account hook leaves the invitation in pending
  # state. SignupAndAccept reloads via find_by_token (still valid post-signup)
  # and asserts the invitation has NOT been accepted yet — the frontend
  # completes the join via an explicit POST /api/invite/:token/accept against
  # the session this endpoint just established.
  describe '#process invitation reload after signup' do
    let(:new_customer) do
      cust = build_mock_customer(
        objid: 'cust-new-123',
        custid: 'cust-new-123',
        extid: 'ext-new-123',
        email: invited_email,
        obscure_email: 'ne***@example.com'
      )
      allow(cust).to receive(:role).and_return('customer')
      allow(cust).to receive(:locale).and_return('en')
      cust
    end

    let(:rate_limiter) { instance_double(Onetime::Security::InviteTokenRateLimiter) }

    let(:account_row) { { id: 123, email: normalized_email, external_id: 'ext-new-123' } }

    # Sequel dataset double for accounts table operations. Exposed as a let
    # so individual contexts can override .first to exercise error branches
    # (e.g. account row missing after create_account).
    let(:accounts_ds) do
      ds = double('accounts_ds')
      allow(ds).to receive(:where).and_return(ds)
      allow(ds).to receive(:first).and_return(account_row)
      allow(ds).to receive(:any?).and_return(false)
      allow(ds).to receive(:update)
      ds
    end

    before do
      allow(Onetime::Security::InviteTokenRateLimiter).to receive(:new)
        .with(client_ip)
        .and_return(rate_limiter)
      allow(rate_limiter).to receive(:check!)
      allow(rate_limiter).to receive(:record_attempt)

      # raise_concerns and post-signup reload both go through find_by_token.
      allow(Onetime::OrganizationMembership).to receive(:find_by_token)
        .with(invite_token)
        .and_return(invitation)
      allow(Onetime::Customer).to receive(:email_exists?)
        .with(normalized_email)
        .and_return(false)

      # Rodauth create_account returns nil on success. The real hook chain
      # (apps/web/auth/config/hooks/account.rb) creates the customer and
      # auto-verifies the SQL account but does NOT call accept! — the
      # invitation stays pending. We model that here.
      allow(Auth::Config).to receive(:create_account).and_return(nil)

      allow(Auth::Database).to receive(:connection).and_return(double(:[] => accounts_ds))

      allow(Onetime::Customer).to receive(:find_by_extid)
        .with('ext-new-123')
        .and_return(new_customer)

      allow(Auth::Logging).to receive(:log_auth_event)
      allow(Familia).to receive(:now).and_return(double(to_i: Time.now.to_i, to_f: Time.now.to_f))
      allow(Familia).to receive(:dbclient).and_return(double(del: true))
    end

    subject(:logic) { described_class.new(strategy_result, valid_params) }

    context 'when the hook leaves the invitation pending (happy path)' do
      before do
        logic.raise_concerns
      end

      it 'reloads the still-pending invitation via find_by_token' do
        expect(Onetime::OrganizationMembership).to receive(:find_by_token)
          .with(invite_token)
          .at_least(:once)
          .and_return(invitation)
        expect(Onetime::OrganizationMembership).not_to receive(:find_by_org_customer)
        logic.process
      end

      it 'returns success data carrying the pending invitation status' do
        allow(invitation).to receive(:status).and_return('pending')
        result = logic.process
        expect(result[:record][:auto_login]).to be true
        expect(result[:record][:role]).to eq('member')
        expect(result[:record][:invitation_status]).to eq('pending')
      end

      it 'creates the Rodauth account via internal_request with the invite_token' do
        expect(Auth::Config).to receive(:create_account).with(
          login: normalized_email,
          password: valid_password,
          params: { 'invite_token' => invite_token }
        )
        logic.process
      end

      it 'returns success_data with the expected record wrapper keys' do
        result = logic.process
        expect(result).to have_key(:record)
        expect(result[:record]).to include(:user_id, :organization, :role, :invitation_status, :auto_login)
      end

      it 'sets up the session for auto-login' do
        logic.process
        expect(session['authenticated']).to be true
        expect(session['external_id']).to eq('ext-new-123')
        expect(session['account_id']).to eq(123)
      end

      it 'logs the pending-accept signup event on the auth logger' do
        expect(auth_logger_double).to receive(:info).with(
          'User signed up; invitation pending explicit accept',
          hash_including(event: 'invite.signup_pending_accept', result: :success)
        )
        logic.process
      end
    end

    context 'when the account row is missing after create_account' do
      # Mirrors signup_and_accept.rb:228 — create_account succeeded with no
      # error, but the followup .where(email: ...).first lookup returns nil.
      # We trigger this by stubbing .first to nil so the account branch raises
      # before the customer-missing branch (which has its own assertion).
      before do
        allow(accounts_ds).to receive(:first).and_return(nil)
        logic.raise_concerns
      end

      it 'raises a form error indicating account creation failed' do
        expect { logic.process }.to raise_error(Onetime::FormError, /Failed to create account/)
      end
    end

    context 'when find_by_token returns nil after signup' do
      # Defensive: if anything wiped token_lookup mid-flight (cache flush,
      # operator action, concurrent revoke), surface a user-visible error
      # rather than handing back a half-baked success.
      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_token)
          .with(invite_token)
          .and_return(invitation, nil)
        logic.raise_concerns
      end

      it 'raises a form error on the token field' do
        expect { logic.process }.to raise_error(Onetime::FormError) do |err|
          expect(err.message).to match(/Invitation no longer available/)
          expect(err.field).to eq(:token)
        end
      end
    end

    context 'when find_by_token returns a non-pending invitation' do
      let(:active_invitation) do
        inv = build_mock_invitation(
          objid: 'inv-active-789',
          token: nil,
          invited_email: invited_email,
          role: 'member',
          organization: organization,
          organization_objid: 'org-test-123',
          status: 'active',
          'pending?' => false,
          'active?' => true,
          'expired?' => false
        )
        allow(inv).to receive(:joined_at).and_return(Time.now.to_i)
        inv
      end

      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_token)
          .with(invite_token)
          .and_return(invitation, active_invitation)
        logic.raise_concerns
      end

      it 'raises a form error on the token field' do
        expect { logic.process }.to raise_error(Onetime::FormError, /Invitation no longer available/)
      end
    end
  end

  # Integration-style tests (require full app boot with Valkey)
  describe 'integration behavior', type: :integration do
    # These tests use ProductionConfigHelper and require:
    # - Valkey running on port 2121
    # - AUTH_DATABASE_URL configured

    it 'POST /api/invite/:token/signup with valid token creates account and accepts invitation'
    it 'POST /api/invite/:token/signup sets session cookie for auto-login'
    it 'POST /api/invite/:token/signup returns 200 with organization details'
    it 'POST /api/invite/:token/signup returns 404 for non-existent token'
    it 'POST /api/invite/:token/signup returns 422 for expired invitation'
    it 'POST /api/invite/:token/signup returns 422 when account already exists'
    it 'POST /api/invite/:token/signup returns 429 when rate limited'
  end
end

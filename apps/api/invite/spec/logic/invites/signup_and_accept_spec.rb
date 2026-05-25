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

  before do
    allow(OT).to receive(:info)
    allow(OT).to receive(:ld)
    allow(OT).to receive(:le)
    allow(OT::Utils).to receive(:normalize_email).and_return(normalized_email)
    allow(OT::Utils).to receive(:obscure_email).and_return('ne***@example.com')
    allow(Auth::Database).to receive(:connection).and_return(mock_auth_db)
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

  describe '#process' do
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

    before do
      allow(Onetime::Security::InviteTokenRateLimiter).to receive(:new)
        .with(client_ip)
        .and_return(rate_limiter)
      allow(rate_limiter).to receive(:check!)
      allow(rate_limiter).to receive(:record_attempt)

      allow(Onetime::OrganizationMembership).to receive(:find_by_token)
        .with(invite_token)
        .and_return(invitation)
      allow(Onetime::Customer).to receive(:email_exists?)
        .with(normalized_email)
        .and_return(false)

      # Mock account creation via Rodauth internal_request
      allow(Auth::Config).to receive(:create_account).and_return(123)

      # Mock CreateCustomer operation
      create_customer_op = instance_double(Auth::Operations::CreateCustomer)
      allow(Auth::Operations::CreateCustomer).to receive(:new).and_return(create_customer_op)
      allow(create_customer_op).to receive(:call).and_return(new_customer)

      # Mock CreateDefaultWorkspace operation
      workspace_op = instance_double(Auth::Operations::CreateDefaultWorkspace)
      allow(Auth::Operations::CreateDefaultWorkspace).to receive(:new).and_return(workspace_op)
      allow(workspace_op).to receive(:call)

      # Mock AcceptInvitation operation
      accept_op = instance_double(Auth::Operations::AcceptInvitation)
      allow(Auth::Operations::AcceptInvitation).to receive(:new).and_return(accept_op)
      allow(accept_op).to receive(:call).and_return({ accepted: true, organization_id: 'org-test-123', role: 'member' })

      # Mock logging
      allow(Auth::Logging).to receive(:log_auth_event)
      allow(Familia).to receive(:now).and_return(double(to_i: Time.now.to_i))
      allow(Familia).to receive(:dbclient).and_return(double(del: true))
    end

    subject(:logic) { described_class.new(strategy_result, valid_params) }

    context 'with valid request (happy path)' do
      before do
        logic.raise_concerns
      end

      it 'creates Rodauth account via internal_request' do
        expect(Auth::Config).to receive(:create_account).with(
          login: normalized_email,
          password: valid_password
        )
        logic.process
      end

      it 'creates Customer in Redis' do
        expect(Auth::Operations::CreateCustomer).to receive(:new).with(
          account_id: 123,
          account: hash_including(id: 123, email: normalized_email),
          db: mock_auth_db
        )
        logic.process
      end

      it 'creates default workspace' do
        expect(Auth::Operations::CreateDefaultWorkspace).to receive(:new)
          .with(customer: new_customer)
        logic.process
      end

      it 'accepts the invitation' do
        expect(Auth::Operations::AcceptInvitation).to receive(:new).with(
          customer: new_customer,
          token: invite_token
        )
        logic.process
      end

      it 'marks account as verified in authdb' do
        accounts_ds = mock_auth_db[:accounts]
        expect(accounts_ds).to receive(:where).with(id: 123).and_return(accounts_ds)
        expect(accounts_ds).to receive(:update).with(status_id: 2)
        logic.process
      end

      it 'sets up session for auto-login' do
        logic.process
        expect(session['authenticated']).to be true
        expect(session['external_id']).to eq('ext-new-123')
      end

      it 'returns success data with record wrapper' do
        result = logic.process
        expect(result).to have_key(:record)
        expect(result[:record]).to include(:user_id, :organization, :role, :joined_at, :auto_login)
      end

      it 'logs the signup event' do
        expect(OT).to receive(:info).with(
          '[SignupAndAccept] User signed up and joined organization',
          hash_including(event: 'invite.signup_accepted', result: :success)
        )
        logic.process
      end
    end

    context 'when Rodauth account creation fails' do
      before do
        logic.raise_concerns
        allow(Auth::Config).to receive(:create_account).and_return(nil)
      end

      it 'raises form error' do
        expect { logic.process }.to raise_error(Onetime::FormError, /Failed to create account/)
      end
    end

    context 'when invitation acceptance fails' do
      before do
        logic.raise_concerns
        accept_op = instance_double(Auth::Operations::AcceptInvitation)
        allow(Auth::Operations::AcceptInvitation).to receive(:new).and_return(accept_op)
        allow(accept_op).to receive(:call).and_return({ accepted: false, reason: 'error' })
      end

      it 'raises form error' do
        expect { logic.process }.to raise_error(Onetime::FormError, /Failed to accept invitation/)
      end
    end
  end

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

    it 'returns joined_at timestamp' do
      data = logic.success_data
      expect(data[:record]).to have_key(:joined_at)
    end

    it 'includes auto_login flag' do
      data = logic.success_data
      expect(data[:record][:auto_login]).to be true
    end
  end

  # Regression: GH #3221 — post-acceptance invitation reload must NOT use
  # find_by_token. The after_create_account hook calls AcceptInvitation, which
  # calls invitation.accept!, which removes the token from token_lookup
  # (pending-only index, cleared for security). Reloading via find_by_token
  # after the hook returns nil → 404 "Invitation not found or expired".
  #
  # Correct behavior: reload via find_by_org_customer, which accept! populates
  # on the now-active membership (org_membership.rb:330-331).
  describe '#process invitation reload after acceptance' do
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

    let(:accepted_invitation) do
      inv = build_mock_invitation(
        objid: 'inv-active-456',
        token: nil, # accept! clears the token
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

    let(:rate_limiter) { instance_double(Onetime::Security::InviteTokenRateLimiter) }

    let(:account_row) { { id: 123, email: normalized_email, external_id: 'ext-new-123' } }

    before do
      allow(Onetime::Security::InviteTokenRateLimiter).to receive(:new)
        .with(client_ip)
        .and_return(rate_limiter)
      allow(rate_limiter).to receive(:check!)
      allow(rate_limiter).to receive(:record_attempt)

      # raise_concerns path: token lookup succeeds (invitation still pending)
      allow(Onetime::OrganizationMembership).to receive(:find_by_token)
        .with(invite_token)
        .and_return(invitation)
      allow(Onetime::Customer).to receive(:email_exists?)
        .with(normalized_email)
        .and_return(false)

      # Rodauth create_account: documented contract returns nil on success.
      # The after_create_account hook (production: apps/web/auth/config/hooks/
      # account.rb) handles CreateCustomer + AcceptInvitation + accept!, which
      # removes the token from token_lookup. We model the hook's side effects
      # via the Customer.find_by_extid + find_by_org_customer stubs below.
      allow(Auth::Config).to receive(:create_account).and_return(nil)

      # Sequel dataset double: chains .where(...).where(...).first/any?/update.
      # raise_concerns calls email_exists_in_authdb? (chained where + .any?);
      # create_rodauth_account / process call .where(id|email).first.
      accounts_ds = double('accounts_ds')
      allow(accounts_ds).to receive(:where).and_return(accounts_ds)
      allow(accounts_ds).to receive(:first).and_return(account_row)
      allow(accounts_ds).to receive(:any?).and_return(false)
      allow(accounts_ds).to receive(:update)
      allow(Auth::Database).to receive(:connection).and_return(double(:[] => accounts_ds))

      allow(Onetime::Customer).to receive(:find_by_extid)
        .with('ext-new-123')
        .and_return(new_customer)

      allow(Auth::Logging).to receive(:log_auth_event)
      allow(Familia).to receive(:now).and_return(double(to_i: Time.now.to_i, to_f: Time.now.to_f))
      allow(Familia).to receive(:dbclient).and_return(double(del: true))
    end

    subject(:logic) { described_class.new(strategy_result, valid_params) }

    context 'when the hook successfully accepted the invitation (happy path)' do
      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
          .with('org-test-123', 'cust-new-123')
          .and_return(accepted_invitation)
        logic.raise_concerns
      end

      it 'reloads the invitation via org_customer_lookup, not token_lookup' do
        # Allow the raise_concerns find_by_token call but assert it is not
        # called during process (token has been removed from token_lookup by
        # the time the hook returns).
        expect(Onetime::OrganizationMembership).not_to receive(:find_by_token)
        expect(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
          .with('org-test-123', 'cust-new-123')
          .and_return(accepted_invitation)
        logic.process
      end

      it 'returns success data with the accepted invitation state' do
        result = logic.process
        expect(result[:record][:auto_login]).to be true
        expect(result[:record][:role]).to eq('member')
      end
    end

    context 'when find_by_org_customer returns nil (hook silently failed)' do
      # AcceptInvitation rescues StandardError and returns {accepted: false}
      # instead of raising. The reload is the safety net that converts that
      # silent failure into a user-visible error.
      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
          .with('org-test-123', 'cust-new-123')
          .and_return(nil)
        logic.raise_concerns
      end

      it 'raises a form error on the token field' do
        expect { logic.process }.to raise_error(Onetime::FormError) do |err|
          expect(err.message).to match(/Failed to accept invitation/)
          expect(err.field).to eq(:token)
        end
      end
    end

    context 'when find_by_org_customer returns a still-pending invitation' do
      # Defense-in-depth: even if a row exists, treat non-active as failure.
      let(:still_pending_invitation) do
        inv = build_mock_invitation(
          objid: 'inv-test-123',
          invited_email: invited_email,
          role: 'member',
          organization: organization,
          organization_objid: 'org-test-123',
          status: 'pending',
          'pending?' => true,
          'active?' => false,
          'expired?' => false
        )
        allow(inv).to receive(:joined_at).and_return(nil)
        inv
      end

      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
          .with('org-test-123', 'cust-new-123')
          .and_return(still_pending_invitation)
        logic.raise_concerns
      end

      it 'raises a form error on the token field' do
        expect { logic.process }.to raise_error(Onetime::FormError, /Failed to accept invitation/)
      end
    end

    context 'when find_by_token is called during process (regression guard)' do
      # The bug: signup_and_accept.rb used to call load_invitation(@token)
      # after the hook, which delegates to find_by_token. If anyone reintroduces
      # that pattern, this spec fails — token_lookup has been wiped by accept!.
      before do
        allow(Onetime::OrganizationMembership).to receive(:find_by_org_customer)
          .with('org-test-123', 'cust-new-123')
          .and_return(accepted_invitation)
        logic.raise_concerns

        # Simulate the real post-acceptance state: token has been removed from
        # token_lookup, so any post-process find_by_token call returns nil.
        allow(Onetime::OrganizationMembership).to receive(:find_by_token)
          .with(invite_token)
          .and_return(nil)
      end

      it 'completes successfully even when find_by_token would return nil' do
        # If process ever calls find_by_token again, load_invitation raises
        # Onetime::RecordNotFound and this expectation fails.
        expect { logic.process }.not_to raise_error
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

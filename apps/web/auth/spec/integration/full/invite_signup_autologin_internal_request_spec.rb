# apps/web/auth/spec/integration/full/invite_signup_autologin_internal_request_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (regression for issue #3221)
# =============================================================================
#
# Pins the post-signup contract from the bug fix in this branch:
#
#   1. POST /api/invite/:token/signup creates the account, auto-verifies it,
#      and skips default-workspace creation (the user is joining an existing
#      org via invite — a personal workspace would be dead state).
#   2. The after_create_account hook does NOT accept the invitation. The
#      token stays valid in token_lookup, the invitation stays in `pending`
#      state. Acceptance happens via the explicit POST /api/invite/:token/
#      accept call the frontend issues against the established session —
#      one acceptance code path for both signup and login flows.
#   3. After the explicit /accept call, the invitation reaches `active` and
#      the customer appears in org.members.
#
# Before the bug fix, the hook auto-accepted via Auth::Operations::AcceptInvitation
# during after_create_account, wiping token_lookup before the user's Accept
# click could resolve it (404), and rendering Decline non-functional.
#
# REQUIREMENTS:
# - Valkey running on port 2121: pnpm run test:database:start
# - AUTH_DATABASE_URL set (SQLite or PostgreSQL)
# - AUTHENTICATION_MODE=full
#
# RUN:
#   source .env.test && pnpm run test:rspec \
#     apps/web/auth/spec/integration/full/invite_signup_autologin_internal_request_spec.rb
#
# =============================================================================

require_relative '../../spec_helper'

RSpec.describe 'Invite signup via Rodauth internal_request (issue #3221)', type: :integration do
  before(:all) do
    require 'onetime'
    require 'onetime/application/registry'
    require 'onetime/auth_config'

    Onetime.auth_config.reload! if Onetime.respond_to?(:auth_config) && Onetime.auth_config.respond_to?(:reload!)
    Onetime::Application::Registry.reset! if Onetime::Application::Registry.respond_to?(:reset!)

    Onetime.boot!(:test, force: true)
    Onetime::Application::Registry.prepare_application_registry
  end

  before do
    unless defined?(Auth::Database) && Auth::Database.connection
      skip 'Auth database not configured (run with AUTH_DATABASE_URL set)'
    end
  end

  let(:test_suffix) { "#{Familia.now.to_i}_#{SecureRandom.hex(4)}" }
  let(:owner_email) { "invite_owner_#{test_suffix}@onetimesecret.com" }
  let(:invited_email) { "invitee_#{test_suffix}@onetimesecret.com" }
  let(:password) { 'TestPassword123!' }

  let(:owner) { Onetime::Customer.create!(email: owner_email, role: 'customer') }
  let(:organization) do
    Onetime::Organization.create!(
      "Invite Autologin Org #{test_suffix}",
      owner,
      owner_email,
      is_default: true,
    )
  end
  let(:invitation) do
    Onetime::OrganizationMembership.create_invitation!(
      organization: organization,
      email: invited_email,
      inviter: owner,
      role: 'member',
    )
  end

  after do
    Auth::Database.connection[:accounts].where(email: invited_email).delete
    invitation&.destroy_with_index_cleanup! rescue nil
    organization&.destroy! rescue nil
    owner&.destroy! rescue nil
    Onetime::Customer.find_by_email(invited_email)&.destroy! rescue nil
  rescue StandardError
    # Non-fatal cleanup error
  end

  it 'creates the account and leaves the invitation pending for explicit accept' do
    # Force lazy lets to materialise (owner, org, invitation) in the documented
    # order so the after_create_account hook sees a valid pending invitation.
    expect(invitation.pending?).to be(true)
    invite_token = invitation.token

    Auth::Config.create_account(
      login: invited_email,
      password: password,
      params: { 'invite_token' => invite_token },
    )

    # Account row exists and is auto-verified (status_id 2 = Verified) by the
    # after_create_account hook since the invite proves email ownership.
    account_row = Auth::Database.connection[:accounts].where(email: invited_email).first
    expect(account_row).not_to be_nil
    expect(account_row[:status_id]).to eq(2)

    # The invitation is NOT yet accepted. Token survives in token_lookup so
    # the frontend's explicit POST /api/invite/:token/accept can complete the
    # join against the session that internal_request established.
    looked_up_via_token = Onetime::OrganizationMembership.find_by_token(invite_token)
    expect(looked_up_via_token).not_to be_nil
    expect(looked_up_via_token.pending?).to be(true)

    # No membership in org.members yet — accept! has not run.
    invitee_customer = Onetime::Customer.find_by_email(invited_email)
    expect(invitee_customer).not_to be_nil
    expect(organization.member?(invitee_customer)).to be(false)
    expect(
      Onetime::OrganizationMembership.find_by_org_customer(
        organization.objid,
        invitee_customer.objid,
      ),
    ).to be_nil

    # Default workspace is intentionally skipped for invite signups — invitees
    # join an existing org, so a personal default workspace would be dead state.
    expect(invitee_customer.verified?).to be(true)

    looked_up_id = Auth::Config.account_id_for_login(login: invited_email)
    expect(looked_up_id).to eq(account_row[:id])
  end

  it 'completes the join when /accept runs after signup' do
    expect(invitation.pending?).to be(true)
    invite_token = invitation.token

    # Create Rodauth account + Customer in one shot. The after_create_account hook
    # (account.rb) creates the Customer record — no manual Customer.create! needed.
    # Prior to the hook-collision fix (#3275), billing.rb's hook overwrote account.rb's,
    # so Customer wasn't created and this test required manual creation.
    Auth::Config.create_account(
      login: invited_email,
      password: password,
      params: { 'invite_token' => invite_token },
    )

    # Customer record now exists via the after_create_account hook chain.
    invitee_customer = Onetime::Customer.find_by_email(invited_email)
    expect(invitee_customer).not_to be_nil

    # Simulate the explicit POST /api/invite/:token/accept the frontend issues
    # with the established session: load the still-pending invitation and call
    # accept!. Org membership flips to active in one step (auto-promote, since
    # requires_admin_approval? is false).
    invitation_for_accept = Onetime::OrganizationMembership.find_by_token(invite_token)
    expect(invitation_for_accept).not_to be_nil
    expect(invitation_for_accept.pending?).to be(true)

    invitation_for_accept.accept!(invitee_customer, provisioning_source: 'invited')

    expect(organization.member?(invitee_customer)).to be(true)

    active_membership = Onetime::OrganizationMembership.find_by_org_customer(
      organization.objid,
      invitee_customer.objid,
    )
    expect(active_membership).not_to be_nil
    expect(active_membership.active?).to be(true)

    # Token consumed on accept — find_by_token must no longer resolve.
    expect(Onetime::OrganizationMembership.find_by_token(invite_token)).to be_nil
  end

  it 'preserves the token after signup so /decline stays functional' do
    expect(invitation.pending?).to be(true)
    invite_token = invitation.token

    Auth::Config.create_account(
      login: invited_email,
      password: password,
      params: { 'invite_token' => invite_token },
    )

    invitation_for_decline = Onetime::OrganizationMembership.find_by_token(invite_token)
    expect(invitation_for_decline).not_to be_nil
    expect(invitation_for_decline.pending?).to be(true)

    invitation_for_decline.decline!

    expect(invitation_for_decline.status).to eq('declined')
    # SQL account intact — the user can still log in as a personal account.
    account_row = Auth::Database.connection[:accounts].where(email: invited_email).first
    expect(account_row).not_to be_nil
  end

  it 'blocks signup when invite_token email does not match login email' do
    expect(invitation.pending?).to be(true)
    invite_token = invitation.token
    other_email  = "other_#{test_suffix}@onetimesecret.com"

    # Email-mismatch validation happens in before_create_account (account.rb).
    # The hook compares the signup email against invitation.invited_email and
    # aborts via throw_rodauth_error if they don't match. This surfaces as
    # InternalRequestError when using internal_request.
    expect {
      Auth::Config.create_account(
        login: other_email,
        password: password,
        params: { 'invite_token' => invite_token },
      )
    }.to raise_error(Rodauth::InternalRequestError)

    # No account written: before_create_account aborted the flow.
    other_account = Auth::Database.connection[:accounts].where(email: other_email).first
    expect(other_account).to be_nil

    # Invitation still resolves by its token (untouched).
    untouched = Onetime::OrganizationMembership.find_by_token(invite_token)
    expect(untouched).not_to be_nil
    expect(untouched.pending?).to be(true)
  ensure
    # Cleanup any orphaned records created if the validation didn't block signup.
    if defined?(other_email)
      Onetime::Customer.find_by_email(other_email)&.destroy!
      db = Auth::Database.connection
      if db.database_type == :sqlite
        db.run('PRAGMA foreign_keys = OFF')
        db[:accounts].where(email: other_email).delete
        db.run('PRAGMA foreign_keys = ON')
      else
        account_row = db[:accounts].where(email: other_email).first
        if account_row
          AuthAccountFactory::RODAUTH_TABLES.each do |table|
            next if table == :accounts
            next unless db.table_exists?(table)
            db[table].where(account_id: account_row[:id]).delete rescue nil
          end
          db[:accounts].where(email: other_email).delete
        end
      end
    end
  end
end

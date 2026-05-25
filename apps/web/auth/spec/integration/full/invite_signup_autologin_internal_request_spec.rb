# apps/web/auth/spec/integration/full/invite_signup_autologin_internal_request_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (regression for issue #3221)
# =============================================================================
#
# Reproduces the bug surfaced by POST /api/invite/:token/signup returning
# 422 "Failed to create account" *after* the account was successfully created
# and the invitation was accepted.
#
# Root cause:
#   Auth::Config.create_account(login:, password:, params: {invite_token:})
#   returns nil when the after_create_account hook sets @invite_accepted = true,
#   which flips create_account_autologin? to true. Under internal_request mode
#   Rodauth's autologin path calls autologin_session('create_account') (which
#   bypasses after_login) followed by create_account_response (which throws
#   :halt via redirect). handle_internal_request catches the halt and returns
#   @internal_request_return_value — but that ivar is only set by the
#   internal_request override of after_login, which autologin_session never
#   triggers. Result: caller sees nil, treats it as failure, raises FormError.
#
# The signature this test pins down (the "bug triad"):
#   1. result of Auth::Config.create_account is nil
#   2. the accounts row was created (account creation actually succeeded)
#   3. the invitation was accepted (after_create_account hook ran to completion,
#      so @invite_accepted = true, so autologin path fired — which is the
#      precise condition that breaks the return value)
#
# After the fix only assertion (1) flips — result must be the account_id.
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

  it 'returns the account_id when invite acceptance triggers autologin' do
    # Force lazy lets to materialise (owner, org, invitation) in the documented
    # order so the after_create_account hook sees a valid pending invitation.
    expect(invitation.pending?).to be(true)
    invite_token = invitation.token

    # Exact call shape used by apps/api/invite/logic/invites/signup_and_accept.rb:200
    result = Auth::Config.create_account(
      login: invited_email,
      password: password,
      params: { 'invite_token' => invite_token },
    )

    # ---- Bug triad ----------------------------------------------------------

    # (2) The account row exists in authdb — proves create_account did NOT bail
    # out early (e.g. before_create_account rejection, login_valid_email?
    # failure, signup-validation block). If this fails the test isn't
    # reproducing #3221; account creation died upstream of the autologin path.
    account_row = Auth::Database.connection[:accounts].where(email: invited_email).first
    expect(account_row).not_to be_nil
    # auto-verified by the hook (status_id 2 = Verified) — invite proves email ownership
    expect(account_row[:status_id]).to eq(2)

    # (3) The invitation was accepted — proves the after_create_account hook
    # reached the @invite_accepted = true line, which is the precondition that
    # makes create_account_autologin? return true.
    activated_membership = Onetime::OrganizationMembership.find_by_org_customer(
      organization.objid,
      Onetime::Customer.find_by_email(invited_email)&.objid,
    )
    expect(activated_membership).not_to be_nil
    expect(activated_membership.active?).to be(true)

    # (1) THE BUG: Auth::Config.create_account returns nil despite (2) + (3)
    # succeeding. This assertion fails today; after the fix it must hold.
    expect(result).not_to be_nil
    expect(result).to eq(account_row[:id])
  end
end

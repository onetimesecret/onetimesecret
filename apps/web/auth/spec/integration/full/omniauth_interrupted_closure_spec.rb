# apps/web/auth/spec/integration/full/omniauth_interrupted_closure_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# Issue: #4830. A closure that stopped after removing the sign-in and before
# deleting the Customer record leaves that record in Redis, marked as closing,
# with no accounts row. A first SSO sign-in with the address must deal with
# it before rodauth-omniauth inserts the accounts row
# (before_omniauth_create_account): finish the closure and provision a new
# record, or refuse with nothing created. Refusing after the insert, in
# EnsureCustomerForAccount, left a committed accounts row with no Customer
# and the SSO identity attached to it, which can neither sign in nor be
# replaced by a new sign-up.
#
# Driven through the real callback, like omniauth_jit_verified_spec.rb.
# interrupted_closures_spec.rb covers the password path and the operation.
#
# RUN:
#   tests/lanes/run full-sqlite \
#     --only apps/web/auth/spec/integration/full/omniauth_interrupted_closure_spec.rb
# =============================================================================

require_relative '../../spec_helper'

RSpec.describe 'First SSO sign-in during an interrupted closure (#4830)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    # Same boot as omniauth_jit_verified_spec.rb.
    require 'onetime'
    require 'onetime/application/registry'
    require 'onetime/auth_config'

    Onetime.auth_config.reload! if Onetime.respond_to?(:auth_config) && Onetime.auth_config.respond_to?(:reload!)
    Onetime::Application::Registry.reset! if Onetime::Application::Registry.respond_to?(:reset!)

    Onetime.boot!(:test, force: true)

    Onetime::Application::Registry.prepare_application_registry

    mounts = Onetime::Application::Registry.mount_mappings.keys
    raise "Auth app not mounted post-boot: #{mounts.inspect}" unless mounts.any? { |m| m.include?('/auth') }
  end

  before { enable_platform_fallback }

  let(:email) { "sso-closure-#{SecureRandom.hex(6)}@closure-test.example.com" }
  let(:uid) { "sub-#{SecureRandom.hex(8)}" }
  let(:accounts) { auth_db[:accounts] }

  # The state a closure leaves when it stops between the auth account and
  # the record: no accounts row, the record still in Redis, marked.
  def interrupted_closure(marked_at:)
    Auth::Config.create_account(login: email, password: AuthTestConstants::TEST_PASSWORD)
    customer = Onetime::Customer.find_by_email(OT::Utils.normalize_email(email)) ||
               raise("sign-up did not create a Customer for #{email}")
    Auth::Operations::RemoveAuthenticationData.call(extid: customer.extid, revoke_sessions: false)
    customer.mark_closure_started!(at: marked_at)
    customer
  end

  def sso_sign_in
    setup_mock_auth(email: email, uid: uid)
    post '/auth/sso/oidc/callback'
    skip 'OmniAuth route not registered (OIDC discovery not available at boot)' if last_response.status == 404
  ensure
    teardown_mock_auth
  end

  def account_rows
    accounts.where(email: OT::Utils.normalize_email(email))
  end

  def identity_rows
    auth_db[:account_identities].where(uid: uid)
  end

  after do
    customer = Onetime::Customer.find_by_email(OT::Utils.normalize_email(email))
    customer&.destroy!
  rescue StandardError
    nil # non-fatal cleanup
  end

  it 'refuses, creating nothing, while the closure is under 15 minutes old' do
    leftover = interrupted_closure(marked_at: Familia.now.to_i - 60)
    allow(Auth::Operations::Customers::Purge).to receive(:new).and_call_original
    allow(Auth::Logging).to receive(:log_auth_event).and_call_original

    sso_sign_in

    expect_auth_error_redirect('account_closing')
    expect(account_rows.count).to eq(0)
    expect(identity_rows.count).to eq(0)
    expect(Auth::Operations::Customers::Purge).not_to have_received(:new)
    expect(leftover.exists?).to be(true)
    expect(Onetime::Customer.load(leftover.objid).closing?).to be(true)
    expect(Auth::Logging).to have_received(:log_auth_event)
      .with(:omniauth_blocked_interrupted_closure, hash_including(external_id: leftover.extid))
  end

  it 'refuses, creating nothing, when the closure cannot be finished' do
    leftover = interrupted_closure(marked_at: Familia.now.to_i - 3600)
    refused  = Auth::Operations::Customers::Purge::Result.new(status: :refused, extid: leftover.extid, custid: nil)
    allow(Auth::Operations::Customers::Purge).to receive(:new)
      .and_return(instance_double(Auth::Operations::Customers::Purge, call: refused))

    sso_sign_in

    expect_auth_error_redirect('account_closing')
    expect(account_rows.count).to eq(0)
    expect(identity_rows.count).to eq(0)
    expect(leftover.exists?).to be(true)
  end

  it 'finishes a stale closure and provisions a new record' do
    leftover = interrupted_closure(marked_at: Familia.now.to_i - 3600)

    sso_sign_in

    expect(last_response.status).to eq(302)
    expect(last_response.location.to_s).not_to include('auth_error=')
    expect(leftover.exists?).to be(false)

    customer = Onetime::Customer.find_by_email(OT::Utils.normalize_email(email))
    expect(customer.extid).not_to eq(leftover.extid)
    expect(customer.closing?).to be(false)
    expect(account_rows.get(:external_id)).to eq(customer.extid)
    expect(identity_rows.count).to eq(1)
  end
end

# apps/web/auth/spec/integration/full/omniauth_jit_verified_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode)
# =============================================================================
#
# Issue: #3973 — SSO/OmniAuth JIT-provisioned customers were left unverified.
#
# THE BUG
# -------
# Auth::Operations::CreateCustomer hard-coded `verified: false` with the
# comment "needs to be updated in after_verify_account". after_verify_account
# fires only in Rodauth's EMAIL verify_account flow, which a JIT SSO user never
# traverses — so the Customer stayed unverified forever while its Rodauth
# accounts row sat at status Verified. That is not cosmetic:
# Onetime::Application::AuthorizationPolicies#has_system_role? does
# `return false unless cust.verified?` BEFORE it looks at the role, so an
# SSO-provisioned colonel/admin could never exercise their role.
#
# WHAT THIS FILE LOCKS IN
# -----------------------
# The HEADLINE change, driven through the REAL Rodauth omniauth callback rather
# than by re-implementing the hook's decision:
#
#   1. POSITIVE — a brand-new platform SSO sign-in (JIT provisioning) yields a
#      Customer with verified? == true and verified_by == 'sso', and an
#      accounts row at STATUS_VERIFIED. If the hook stops passing the new
#      CreateCustomer parameters, this fails.
#   2. NEGATIVE — a customer NOT provisioned via SSO (the plain CreateCustomer
#      call every password signup makes) is NOT verified. This is the guard
#      against the rejected first attempt at this fix, which verified almost
#      anyone by checking status_id on the shared login path.
#   3. NEGATIVE — an IdP that EXPLICITLY asserts email_verified: false does not
#      get the verified stamp, even though Rodauth opened its account.
#
# Layer note: apps/web/auth/spec/integration/full/omniauth_account_creation_spec.rb
# pins the CreateCustomer PARAMETER contract in isolation. This file pins the
# WIRING — that the production hook actually passes them, and on what gate.
#
# REQUIREMENTS:
# - Valkey running on port 2163: pnpm run test:database:start
# - AUTHENTICATION_MODE=full, AUTH_DATABASE_URL (SQLite in-memory; rake sets it)
#
# RUN:
#   tests/lanes/run full \
#     --only apps/web/auth/spec/integration/full/omniauth_jit_verified_spec.rb
# =============================================================================

require_relative '../../spec_helper'

RSpec.describe 'OmniAuth JIT provisioning sets verified (#3973)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    # Same boot as omniauth_trusted_link_spec.rb: force a clean reboot so
    # provider registration runs against this suite's WebMock stubs + ENV, and
    # assert the auth app actually mounted (a silent empty registry would turn
    # every callback into a 404 -> skip).
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

  let(:accounts) { auth_db[:accounts] }

  # Customers created by the callback are found by email afterwards; track them
  # so the shared in-memory DB / Valkey do not accumulate across examples.
  let(:created_customers) { [] }

  after do
    created_customers.each do |customer|
      customer.destroy! if customer&.exists?
    rescue StandardError
      nil # non-fatal cleanup
    end
  end

  def jit_email(prefix)
    "#{prefix}-#{SecureRandom.hex(6)}@jit-verified-test.example.com"
  end

  # The Customer the callback JIT-provisioned, or nil.
  def customer_for(email)
    normalized = OT::Utils.normalize_email(email)
    return nil unless Onetime::Customer.email_exists?(normalized)

    customer = Onetime::Customer.find_by_email(normalized)
    created_customers << customer
    customer
  end

  # ==========================================================================
  # 1. POSITIVE — JIT SSO sign-in produces a VERIFIED customer
  # ==========================================================================

  describe 'a new platform SSO sign-in' do
    before { enable_platform_fallback }

    it 'provisions a verified customer stamped verified_by=sso' do
      email = jit_email('jit-verified')
      uid   = "sub-#{SecureRandom.hex(8)}"

      setup_mock_auth(email: email, uid: uid)
      begin
        post '/auth/sso/oidc/callback'

        if last_response.status == 404
          skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
        end
        expect(last_response.status).to eq(302),
          "Expected a post-login redirect, got #{last_response.status}: #{last_response.body}"

        # Rodauth JIT-created the account, and (rodauth-omniauth 0.6.2
        # _omniauth_new_account) opened it at Verified. This is the fact the
        # hook mirrors — assert it so a failure below is unambiguous about
        # which side moved.
        account = accounts.where(email: OT::Utils.normalize_email(email)).first
        expect(account).not_to be_nil, 'Expected the callback to JIT-create an accounts row'
        expect(account[:status_id]).to eq(AuthTestConstants::STATUS_VERIFIED)

        customer = customer_for(email)
        expect(customer).not_to be_nil, 'Expected the callback to JIT-create a Customer'
        expect(customer.provisioning_origin.to_s).to eq('sso_jit')

        # THE HEADLINE ASSERTION.
        expect(customer.verified?).to be(true),
          'SSO JIT-provisioned customer must be verified — has_system_role? gates on it'
        expect(customer.verified_by.to_s).to eq('sso')
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # 2. NEGATIVE — a non-SSO customer is NOT verified
  # ==========================================================================
  #
  # The rejected first attempt at this fix reconciled on the LOGIN path guarded
  # only on status_id == Verified. With verify_account disabled that is true for
  # ordinary password accounts too, so it verified almost everyone. The fix is
  # scoped to the SSO JIT provisioning hook, which means the ordinary
  # CreateCustomer call — the one every password signup makes — must still
  # produce an unverified customer even when its accounts row is Verified.

  describe 'a customer not provisioned via SSO' do
    it 'is not verified, even with a Verified accounts row' do
      email      = jit_email('non-sso')
      normalized = OT::Utils.normalize_email(email)
      account_id = accounts.insert(
        email: normalized,
        status_id: AuthTestConstants::STATUS_VERIFIED,
      )

      begin
        customer = Auth::Operations::CreateCustomer.new(
          account_id: account_id,
          account: { id: account_id, email: normalized },
          provisioning_origin: 'canonical_signup',
        ).call
        created_customers << customer

        expect(customer.provisioning_origin.to_s).to eq('canonical_signup')
        expect(customer.verified?).to be(false),
          'A non-SSO signup must not inherit verification from its accounts row'
        expect(customer.verified_by.to_s).to eq('')
      ensure
        accounts.where(id: account_id).delete
      end
    end
  end

  # ==========================================================================
  # 3. NEGATIVE — an explicit email_verified: false vetoes the stamp
  # ==========================================================================
  #
  # Absence of the claim is NOT a veto (most enterprise IdPs never emit it), but
  # an IdP that actively says the address is unverified is taken at its word.

  describe 'an IdP asserting email_verified: false' do
    before { enable_platform_fallback }

    it 'provisions the customer unverified' do
      email = jit_email('jit-unverified-claim')
      uid   = "sub-#{SecureRandom.hex(8)}"

      OmniAuth.config.test_mode = true
      OmniAuth.config.allowed_request_methods = %i[get post]
      OmniAuth.config.mock_auth[:oidc] = OmniAuth::AuthHash.new({
        provider: 'oidc',
        uid: uid,
        info: { email: email, name: 'Unverified Claim', email_verified: false },
        extra: { raw_info: { sub: uid, email: email, email_verified: false } },
      })

      begin
        post '/auth/sso/oidc/callback'

        if last_response.status == 404
          skip 'OmniAuth route not registered (OIDC discovery not available at boot)'
        end

        customer = customer_for(email)
        skip 'Callback did not JIT-provision a customer' if customer.nil?

        expect(customer.verified?).to be(false),
          'An explicit email_verified: false assertion must veto the verified stamp'
        expect(customer.verified_by.to_s).to eq('')
      ensure
        teardown_mock_auth
      end
    end
  end

  # ==========================================================================
  # The claim reader, at its own boundary
  # ==========================================================================
  #
  # Cheap and exhaustive on the shapes the callback specs cannot vary quickly:
  # string vs symbol keys, info vs extra.raw_info, stringified booleans, and the
  # absence that must NOT read as a veto.

  # Named rather than passed as a constant: the auth app (and therefore
  # Auth::Config) is only loaded by the before(:all) boot above, well after
  # RSpec evaluates this file's describe arguments.
  describe 'Auth::Config::Hooks::OmniAuth.idp_asserts_unverified_email?' do
    subject(:veto?) { Auth::Config::Hooks::OmniAuth.method(:idp_asserts_unverified_email?) }

    it 'vetoes on an explicit false in info' do
      expect(veto?.call(info: { 'email_verified' => false }, extra: nil)).to be true
      expect(veto?.call(info: { email_verified: false }, extra: nil)).to be true
      expect(veto?.call(info: { 'email_verified' => 'false' }, extra: nil)).to be true
    end

    it 'vetoes on an explicit false in extra.raw_info' do
      expect(veto?.call(info: {}, extra: { 'raw_info' => { 'email_verified' => false } })).to be true
      expect(veto?.call(info: nil, extra: { raw_info: { email_verified: false } })).to be true
    end

    it 'does not veto when the claim is absent, nil, or true' do
      expect(veto?.call(info: nil, extra: nil)).to be false
      expect(veto?.call(info: {}, extra: {})).to be false
      expect(veto?.call(info: { 'name' => 'No Claim' }, extra: { 'raw_info' => { 'sub' => 'x' } })).to be false
      expect(veto?.call(info: { 'email_verified' => true }, extra: nil)).to be false
      expect(veto?.call(info: { 'email_verified' => 'true' }, extra: nil)).to be false
    end

    it 'prefers info over extra.raw_info' do
      expect(
        veto?.call(info: { 'email_verified' => true }, extra: { 'raw_info' => { 'email_verified' => false } }),
      ).to be false
    end
  end
end

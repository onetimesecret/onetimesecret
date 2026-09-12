# apps/web/auth/spec/integration/full/mfa_billing_redirect_intent_spec.rb
#
# frozen_string_literal: true

# Regression coverage for issue #4306 — "MFA login silently discards the
# selected plan".
#
# What is under test
# ------------------
# The pending_plan_intent lifecycle across the MFA hop, under the
# peek-then-consume contract:
#
#   apps/web/auth/config/hooks/login.rb, after_login:
#     add_billing_redirect_to_response only when NO second factor is pending
#     (`!mfa_decision&.requires_mfa?` — the same condition that picked the
#     MFA-required vs full-session-sync branch).
#
#   apps/web/auth/config/hooks/two_factor.rb, after_two_factor_authentication:
#     add_billing_redirect_to_response — for MFA logins, THIS is the completed
#     authentication point that surfaces the intent.
#
# SURFACING IS A PEEK. Building billing_redirect no longer deletes the Redis
# key: until the authenticated handoff succeeds, every completed login
# re-surfaces the same billing_redirect (retry-on-failure, bounded by the
# field's 24h TTL). Consumption is Onetime::Customer#consume_pending_plan_intent!,
# invoked when the authenticated client enters the billing plans flow
# (Billing::Controllers::BillingController#subscription_status — the endpoint
# PlanSelector.vue hits on mount; endpoint-level coverage lives in
# apps/web/billing/spec/controllers/billing_controller_spec.rb, because that
# Otto app cannot be mounted inside this Rodauth-only harness — here the
# consumption unit is exercised invocation-level, on a real Redis-backed
# Customer).
#
# The original bug: after_login called add_billing_redirect_to_response
# unconditionally AND surfacing deleted the key, so an MFA-gated login
# consumed the intent on the primary-factor response — which the SPA's MFA
# flow never reads — leaving after_two_factor_authentication a guaranteed
# no-op. Net: MFA users lost their selected plan.
#
# Why an inline Roda app rather than the mounted /auth app
# --------------------------------------------------------
# Same reason as mfa_awaiting_flag_clear_spec.rb (see its header): the booted
# app pins `mfa: false` so no real OTP auth can complete there — and it boots
# with billing disabled, so config.rb never registers Hooks::Billing. This
# spec mounts a Rodauth app wired with the REAL production modules —
# Auth::Config::Features::MFA and Auth::Config::Hooks::Login/MFA/TwoFactor/
# Billing — so the hook bodies executing here are the production hook bodies,
# not copies of them (billing.rb's build_billing_redirect_info reports
# valid:false when billing_config is disabled, but capture/consumption — the
# subject of this spec — is unconditional once the hooks are wired).
#
# REQUIREMENTS: Valkey on port 2163 (pnpm run test:database:start).
#
# RUN:
#   AUTHENTICATION_MODE=full AUTH_DATABASE_URL=sqlite::memory: \
#     pnpm run test:rspec apps/web/auth/spec/integration/full/mfa_billing_redirect_intent_spec.rb

require_relative '../../spec_helper'
require 'rack/test'
require 'rotp'
require 'bcrypt'

require_relative '../../support/auth_test_constants'

RSpec.describe 'MFA login preserves pending_plan_intent (issue #4306)', type: :integration do
  include Rack::Test::Methods

  before(:all) do
    # Loads the real Auth::Config along with Auth::Config::Hooks::* and
    # Auth::Operations::*, and connects Familia to the test datastore. Never
    # fabricate the Auth::Config constant here — see the note in
    # pending_plan_intent_flow_spec.rb.
    boot_onetime_app
  end

  let(:db) { create_test_database }
  let(:password) { 'correct horse battery staple' }
  let(:email) { "billing-mfa-#{SecureRandom.hex(6)}@integration-test.example.com" }

  # The accounts row and the Customer are one subject: external_id must equal
  # customer.extid or extract_pending_plan_intent_from_customer resolves nil.
  let(:customer) do
    cust = Onetime::Customer.new(email: email)
    cust.save
    cust
  end

  let(:account_id) do
    id = db[:accounts].insert(
      email: email,
      status_id: AuthTestConstants::STATUS_VERIFIED,
      external_id: customer.extid,
    )
    db[:account_password_hashes].insert(id: id, password_hash: BCrypt::Password.create(password))
    id
  end

  let(:intent_json) do
    { product: 'identity_plus_v1', interval: 'monthly' }.to_json
  end

  # Rodauth app wired with the production MFA feature config and the
  # production login/MFA/two-factor/billing hooks. Registration order mirrors
  # config.rb: TwoFactor after the MFA feature (two_factor_base must exist),
  # Billing last (it defines helper methods only — no hooks; see the NOTE
  # block in hooks/billing.rb).
  let(:app) do
    app_db = db

    Class.new(Roda) do
      plugin :sessions, secret: SecureRandom.hex(64)
      plugin :json
      plugin :json_parser
      plugin :halt

      plugin :rodauth do
        db app_db
        enable :base, :json, :login, :logout
        only_json? true
        login_column :email
        hmac_secret SecureRandom.hex(32)

        Auth::Config::Features::MFA.configure(self)

        Auth::Config::Hooks::Login.configure(self)
        Auth::Config::Hooks::MFA.configure(self)
        Auth::Config::Hooks::TwoFactor.configure(self)
        Auth::Config::Hooks::Billing.configure(self)
      end

      route do |r|
        r.rodauth
      end
    end
  end

  # Enrolls OTP through Rodauth's real two-step JSON otp-setup flow and
  # returns the shared secret, leaving the account logged out. IMPORTANT:
  # enrollment performs a (then no-MFA) login, which runs the billing
  # surfacing path — so examples must set pending_plan_intent AFTER this,
  # never before (surfacing no longer deletes, but an example about "the
  # first response that carries billing_redirect" still must not have an
  # earlier login in its history).
  let(:otp_secret) do
    account_id
    status, = login!
    raise "otp enrollment: login failed (#{status})" unless status == 200

    _, setup = post_json('/otp-setup', {})
    secret   = setup['otp_setup']
    raise "otp enrollment: no otp_setup in #{setup.inspect}" if secret.to_s.empty?

    status, body = post_json(
      '/otp-setup',
      otp_setup: secret,
      otp_raw_secret: setup['otp_raw_secret'],
      otp_code: ROTP::TOTP.new(secret).now,
      password: password,
    )
    raise "otp enrollment: setup failed (#{status}) #{body.inspect}" unless status == 200

    # Backdate last_use so the fresh TOTP code in the example is not rejected
    # as a same-interval replay (see mfa_awaiting_flag_clear_spec.rb).
    db[:account_otp_keys].where(id: account_id).update(last_use: Time.now - 300)

    post_json('/logout', {})
    clear_cookies

    secret
  end

  def parsed_body
    JSON.parse(last_response.body)
  rescue JSON::ParserError
    {}
  end

  def post_json(path, body)
    post(path, body.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json')
    [last_response.status, parsed_body]
  end

  def login!
    post_json('/login', login: email, password: password)
  end

  def current_otp_code(secret)
    ROTP::TOTP.new(secret).now
  end

  def stored_intent
    customer.pending_plan_intent.value.to_s
  end

  before do
    # Delivery is best-effort in production (safe_execute) and not under test.
    allow(Onetime::Jobs::Publisher).to receive(:enqueue_email).and_return(true)
  end

  describe 'a login with no second factor enrolled' do
    it 'returns billing_redirect on the login response and the intent SURVIVES (peek)' do
      account_id
      customer.pending_plan_intent = intent_json

      status, body = login!

      expect(status).to eq(200)
      expect(body).to have_key('billing_redirect')
      expect(body['billing_redirect']).to include(
        'product' => 'identity_plus_v1',
        'interval' => 'monthly',
      )
      # PEEK, not consume: the client may crash before it reaches the plans
      # page, so the Redis key must outlive this response.
      expect(stored_intent).to eq(intent_json)
    end

    it 're-surfaces billing_redirect on a second login before the handoff (retry-on-failure)' do
      account_id
      customer.pending_plan_intent = intent_json
      login!
      post_json('/logout', {})
      clear_cookies

      status, body = login!

      expect(status).to eq(200)
      expect(body).to have_key('billing_redirect')
      expect(body['billing_redirect']).to include(
        'product' => 'identity_plus_v1',
        'interval' => 'monthly',
      )
      expect(stored_intent).to eq(intent_json)
    end

    it 'consume_pending_plan_intent! deletes the key exactly once (the handoff chokepoint)' do
      # Invocation-level: the production consumption unit against the real
      # Redis key. The HTTP wiring (subscription_status calls this for the
      # authenticated customer) is asserted in the billing controller spec —
      # the billing Otto app cannot be mounted inside this Rodauth harness.
      account_id
      customer.pending_plan_intent = intent_json

      expect(customer.consume_pending_plan_intent!).to be(true)
      expect(stored_intent).to eq('')

      # Idempotent no-op when absent.
      expect(customer.consume_pending_plan_intent!).to be(false)
    end

    it 'returns no billing_redirect on a login after consumption (no replay)' do
      account_id
      customer.pending_plan_intent = intent_json
      login!
      post_json('/logout', {})
      clear_cookies

      customer.consume_pending_plan_intent!

      status, body = login!

      expect(status).to eq(200)
      expect(body).not_to have_key('billing_redirect')
    end
  end

  describe 'a login that requires MFA' do
    it 'does NOT surface the intent on the mfa_required response' do
      otp_secret
      customer.pending_plan_intent = intent_json

      status, body = login!

      expect(status).to eq(200)
      expect(body['mfa_required']).to be(true)
      # The SPA's MFA flow never reads billing_redirect off this response;
      # surfacing it here would just be noise on a half-finished login.
      expect(body).not_to have_key('billing_redirect')
      # The Redis key survives untouched for the second factor.
      expect(stored_intent).to eq(intent_json)
    end

    it 'returns billing_redirect on OTP completion and the intent SURVIVES (peek)' do
      secret = otp_secret
      customer.pending_plan_intent = intent_json
      login!

      status, body = post_json('/otp-auth', otp_code: current_otp_code(secret))

      expect(status).to eq(200)
      expect(body).to have_key('billing_redirect')
      expect(body['billing_redirect']).to include(
        'product' => 'identity_plus_v1',
        'interval' => 'monthly',
      )
      # Same peek contract as the no-MFA path: the key outlives the response.
      expect(stored_intent).to eq(intent_json)
    end

    it 'leaves the intent untouched when the TOTP attempt fails' do
      otp_secret
      customer.pending_plan_intent = intent_json
      login!

      status, = post_json('/otp-auth', otp_code: '000000')

      expect(status).not_to eq(200)
      expect(stored_intent).to eq(intent_json)
    end

    it 're-surfaces billing_redirect on a full re-login before the handoff' do
      secret = otp_secret
      customer.pending_plan_intent = intent_json
      login!
      post_json('/otp-auth', otp_code: current_otp_code(secret))
      post_json('/logout', {})
      clear_cookies

      # Re-usable code needs a fresh interval; backdate again.
      db[:account_otp_keys].where(id: account_id).update(last_use: Time.now - 300)

      _, first = login!
      status, body = post_json('/otp-auth', otp_code: current_otp_code(secret))

      expect(status).to eq(200)
      # Primary-factor response of an MFA login never carries it...
      expect(first).not_to have_key('billing_redirect')
      # ...but the completed re-login does, because the handoff never happened.
      expect(body).to have_key('billing_redirect')
      expect(stored_intent).to eq(intent_json)
    end

    it 'returns no billing_redirect on a full re-login after consumption' do
      secret = otp_secret
      customer.pending_plan_intent = intent_json
      login!
      post_json('/otp-auth', otp_code: current_otp_code(secret))
      post_json('/logout', {})
      clear_cookies

      customer.consume_pending_plan_intent!

      # Re-usable code needs a fresh interval; backdate again.
      db[:account_otp_keys].where(id: account_id).update(last_use: Time.now - 300)

      _, first = login!
      status, body = post_json('/otp-auth', otp_code: current_otp_code(secret))

      expect(status).to eq(200)
      expect(first).not_to have_key('billing_redirect')
      expect(body).not_to have_key('billing_redirect')
    end
  end
end

# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../support/mfa_flow_helper'

RSpec.describe 'Auth router MFA-pending session gate', :full_auth_mode, type: :integration do
  include MfaFlowHelper

  let(:email) { "mfa-pending-router-#{SecureRandom.hex(6)}@example.com" }
  let(:account_id) { seed_account_with_password(email) }

  before do
    account_id
    @secret, = provision_totp(email)
    allow_immediate_otp_reuse!(account_id)

    csrf_json_post('/auth/login', login: email, password: AuthTestConstants::TEST_PASSWORD)
    expect(last_response.status).to eq(200), last_response.body
    expect(json_body['mfa_required']).to be(true)
  end

  it 'refuses account reads and session mutations without leaking metadata, then completes MFA' do
    clear_body_headers
    get '/auth/account', {}, 'HTTP_ACCEPT' => 'application/json'

    expect_mfa_pending_refusal
    expect(last_request.env.fetch(Onetime::CustomerSessionEvaluator::ENV_KEY).reason).to eq(:awaiting_mfa)

    expect_any_instance_of(Auth::Config).not_to receive(:remove_all_active_sessions_except_current)
    csrf_json_post('/auth/remove-all-active-sessions', {})

    expect_mfa_pending_refusal
    expect(last_request.env.fetch(Onetime::CustomerSessionEvaluator::ENV_KEY).reason).to eq(:awaiting_mfa)

    csrf_json_post('/auth/otp-auth', otp_code: ROTP::TOTP.new(@secret).now)
    expect(last_response.status).to eq(200), last_response.body

    clear_body_headers
    get '/auth/account', {}, 'HTTP_ACCEPT' => 'application/json'
    expect(last_response.status).to eq(200), last_response.body
    expect(json_body).to include('id' => account_id, 'email' => email)
  end

  it 'refuses anonymous account-lifecycle routes so the MFA challenge cannot be side-stepped' do
    csrf_json_post('/auth/reset-password-request', login: email)
    expect_mfa_pending_refusal

    csrf_json_post('/auth/create-account', login: "another-#{email}", password: AuthTestConstants::TEST_PASSWORD)
    expect_mfa_pending_refusal

    # The challenge remains completable — a refused probe did not strand the session.
    csrf_json_post('/auth/otp-auth', otp_code: ROTP::TOTP.new(@secret).now)
    expect(last_response.status).to eq(200), last_response.body
  end

  def expect_mfa_pending_refusal
    expect(last_response.status).to eq(401)
    expect(json_body).to eq('error' => 'Authentication required')
    expect(last_response.body).not_to include(email)
    expect(last_response.body).not_to include(account_id.to_s)
  end
end

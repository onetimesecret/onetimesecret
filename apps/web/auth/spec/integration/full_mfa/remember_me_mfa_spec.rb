# apps/web/auth/spec/integration/full_mfa/remember_me_mfa_spec.rb
#
# frozen_string_literal: true

# "Remember me" across a two-phase login (apps/web/auth/config/features/
# remember_me.rb). The `remember-me` parameter arrives with the password, but
# the session is not signed in until the second factor, so the first phase
# only holds the choice and the second remembers the session.
#
# LANE: full-mfa (tests/lanes/run full-mfa).

require_relative '../../spec_helper'
require_relative '../../support/mfa_flow_helper'

RSpec.describe 'Remember me across the second factor', :full_auth_mode, type: :integration do
  include MfaFlowHelper

  let(:email) { "remember-mfa-#{SecureRandom.hex(6)}@example.com" }
  let(:account_id) { seed_account_with_password(email) }

  before do
    account_id
    @secret, = provision_totp(email)
    allow_immediate_otp_reuse!(account_id)
  end

  def session_blob
    db    = Familia.dbclient
    codec = Onetime::SessionCodec.from_config
    key   = Onetime::Operations::Sessions::Store.find_key(db, rack_mock_session.cookie_jar['onetime.session'])
    Onetime::Operations::Sessions::Store.load_data(db, key, codec: codec)
  end

  def current_row
    auth_db[:account_active_session_keys]
      .where(account_id: account_id, session_id: session_blob.fetch('active_session_id_hmac'))
      .first
  end

  def password_step(**extra)
    csrf_json_post('/auth/login', { login: email, password: AuthTestConstants::TEST_PASSWORD }.merge(extra))
    expect(last_response.status).to eq(200), last_response.body
    expect(json_body['mfa_required']).to be(true)
  end

  def otp_step
    csrf_json_post('/auth/otp-auth', otp_code: ROTP::TOTP.new(@secret).now)
    expect(last_response.status).to eq(200), last_response.body
  end

  it 'holds the choice through the password step and remembers the session at the second factor', :aggregate_failures do
    password_step('remember-me' => true)

    expect(session_blob).not_to have_key('remember_until')
    expect(session_blob['remember_me_pending']).to be(true)
    expect(current_row[:remember_until]).to be_nil

    otp_step

    expect(session_blob['remember_until']).to be > (Time.now.to_i + Onetime::RememberMe::DURATION - 120)
    expect(session_blob).not_to have_key('remember_me_pending')
    expect(current_row[:remember_until]).not_to be_nil
  end

  it 'leaves an unchecked two-phase login a default session', :aggregate_failures do
    password_step('remember-me' => false)
    otp_step

    expect(session_blob).not_to have_key('remember_until')
    expect(session_blob).not_to have_key('remember_me_pending')
    expect(current_row[:remember_until]).to be_nil
  end
end

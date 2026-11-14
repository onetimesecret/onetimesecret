# apps/web/auth/spec/integration/full_mfa/otp_code_replay_spec.rb
#
# frozen_string_literal: true

# OTP code replay within the drift window (GHSA-26qw-xq5q-hv9w, fixed in
# rodauth 2.50.0).
#
# Rodauth accepts the code for the time step before and after the server's
# (otp_drift, 30 seconds, the default: features/mfa.rb does not set it). The
# reuse guard is `after: otp_last_use`, which refuses every time step up to
# the one last_use falls in. What makes it work is the value written to
# account_otp_keys.last_use on a successful check: the start of the accepted
# code's time step, which ROTP's verify returns. A code for the NEXT time step
# then moves last_use into that step, and the same code is refused from then
# on. Before 2.50.0 the column got the time of the check, which is one step
# short of such a code, and the code was accepted again 30 seconds later.
#
# The app checks a code in three places, and each has to store the step:
#   - POST /auth/otp-setup, where the setup code's step becomes the first
#     last_use (rodauth 82a25ce6, after the 2.50.0 tag; 2.50.0 leaves the
#     column's default, the time of setup);
#   - POST /auth/otp-auth, Rodauth's own route;
#   - POST /auth/reauth, where Auth::Operations::Reauthenticate calls
#     otp_valid_code? and otp_update_last_use itself. Rodauth carries the
#     accepted step from the first call to the second in an instance
#     variable, so both calls have to stay on the one Rodauth instance.
#
# Asserted here against the real /auth routes:
#   - a code for the next time step is accepted and last_use is the start of
#     that step, on all three routes;
#   - the same code sent again is refused;
#   - the code for the time step right after the last one used is accepted
#     without waiting out an interval, after a sign-in and right after setup
#     (rodauth 2.50.0 itself refuses it on PostgreSQL, and after setup on
#     every database; the fork is pinned past the release for this).
#
# LANE: full-mfa (tests/lanes/run full-mfa).

require_relative '../../spec_helper'
require_relative '../../support/mfa_flow_helper'

RSpec.describe 'OTP code replay within the drift window (GHSA-26qw-xq5q-hv9w)', :full_auth_mode, type: :integration do
  include MfaFlowHelper

  let(:email) { "otp-replay-#{SecureRandom.hex(6)}@example.com" }
  let(:account_id) { seed_account_with_password(email) }
  let(:totp) { ROTP::TOTP.new(@secret) }

  before { account_id }

  # The start of the 30-second time step `time` falls in, as epoch seconds:
  # what ROTP's verify returns for a code of that step.
  def step_start(time)
    time.to_i / totp.interval * totp.interval
  end

  def stored_last_use
    auth_db[:account_otp_keys].where(id: account_id).get(:last_use).to_i
  end

  def password_step
    csrf_json_post('/auth/login', login: email, password: AuthTestConstants::TEST_PASSWORD)
    expect(last_response.status).to eq(200), last_response.body
    expect(json_body['mfa_required']).to be(true)
  end

  def otp_step(code)
    csrf_json_post('/auth/otp-auth', otp_code: code)
  end

  def reauth(code)
    csrf_json_post('/auth/reauth', method: 'password', password: AuthTestConstants::TEST_PASSWORD, otp_code: code)
  end

  context 'after a sign-in' do
    before do
      @secret, = provision_totp(email)
      allow_immediate_otp_reuse!(account_id)
    end

    it 'stores the time step of a next-step code at sign-in and refuses the code a second time', :aggregate_failures do
      now       = Time.now
      next_code = totp.at(now + totp.interval)

      password_step
      otp_step(next_code)
      expect(last_response.status).to eq(200), last_response.body
      expect(stored_last_use).to eq(step_start(now + totp.interval))

      clear_cookies
      password_step
      otp_step(next_code)
      expect(last_response.status).to eq(401), last_response.body
      expect(json_body['field-error'].first).to eq('otp_code')
      expect(stored_last_use).to eq(step_start(now + totp.interval))
    end

    it 'accepts the next time step right after a use at re-authentication and stores that step', :aggregate_failures do
      now = Time.now

      password_step
      otp_step(totp.at(now))
      expect(last_response.status).to eq(200), last_response.body
      expect(stored_last_use).to eq(step_start(now))

      # No rewind of last_use here: the code is one time step after the one
      # just used, and that is enough.
      next_code = totp.at(now + totp.interval)
      reauth(next_code)
      expect(last_response.status).to eq(200), last_response.body
      expect(json_body).to eq('success' => 'Re-authentication complete')
      expect(stored_last_use).to eq(step_start(now + totp.interval))

      reauth(next_code)
      expect(last_response.status).to eq(401), last_response.body
      expect(json_body['error_code']).to eq('invalid_otp')
      expect(stored_last_use).to eq(step_start(now + totp.interval))
    end
  end

  # No rewind of last_use in this context: what setup stored is under test.
  context 'right after setup' do
    it 'stores the time step of a next-step setup code and refuses that code at sign-in', :aggregate_failures do
      now = Time.now
      @secret, = provision_totp(email, code_time: now + ROTP::DEFAULT_INTERVAL)
      expect(stored_last_use).to eq(step_start(now + totp.interval))

      password_step
      otp_step(totp.at(now + totp.interval))
      expect(last_response.status).to eq(401), last_response.body
      expect(json_body['field-error'].first).to eq('otp_code')
      expect(stored_last_use).to eq(step_start(now + totp.interval))
    end

    it 'accepts the code for the time step after the setup code at sign-in', :aggregate_failures do
      now = Time.now
      @secret, = provision_totp(email, code_time: now)
      expect(stored_last_use).to eq(step_start(now))

      password_step
      otp_step(totp.at(now + totp.interval))
      expect(last_response.status).to eq(200), last_response.body
      expect(stored_last_use).to eq(step_start(now + totp.interval))
    end
  end
end

# apps/web/auth/spec/support/mfa_flow_helper.rb
#
# frozen_string_literal: true

require_relative 'auth_test_constants'
require_relative 'auth_request_helper'
require_relative 'account_seed_helper'

# =============================================================================
# MFA Lane Helper (integration/full_mfa/)
# =============================================================================
#
# The shared machinery for specs in apps/*/*/spec/integration/full_mfa/: the
# lane bootstrap plus OTP provisioning through Rodauth's OWN JSON setup flow.
#
# WHY A SHARED HELPER RATHER THAN A PER-SPEC MIRROR: everything here is coupled
# to Rodauth's OTP CONFIGURATION (otp_keys_use_hmac?,
# two_factor_modifications_require_password?, the otp_setup/otp_raw_secret/
# recovery-code param names, the two-phase otp-setup contract). A Rodauth
# upgrade or a config flip breaks every copy at once, so a mirrored copy is a
# second place to forget. Route DRIVING stays in each spec — that is the part
# that genuinely differs (link-sso vs sso-link-confirm) and the part a mirror
# is for. Compare support/oauth_flow_helper.rb, included by four full/ specs.
#
# LOAD-TIME SIDE EFFECT — AUTH_MFA_ENABLED: requiring this file sets
# AUTH_MFA_ENABLED=true. It must be set before the suite's FIRST boot
# (FullModeSuiteDatabase.setup! runs from a config-level before(:context) hook,
# ahead of any group-level hook) so config.rb loads the Rodauth OTP feature
# set. The rake lane already exports it; doing it here makes a direct
# `rspec <one file>` invocation work too, and means a NEW spec in this
# directory cannot forget it. Requiring this file outside the full_mfa lane
# would leak MFA into that process's one-shot Auth::Config boot — don't.
#
# Usage (after `require_relative '../../spec_helper'`):
#
#   require_relative '../../support/mfa_flow_helper'
#
#   RSpec.describe '...', :full_auth_mode, type: :integration do
#     include MfaFlowHelper          # brings Rack::Test, `app`, `identities`,
#                                    # the OTP-feature guard, and the helpers
#
#     it '...' do
#       account_id     = seed_account_with_password(email)
#       secret, codes  = provision_totp(email)
#       allow_immediate_otp_reuse!(account_id)
#       csrf_json_post('/auth/otp-auth', otp_code: ROTP::TOTP.new(secret).now)
#     end
#   end
#
# Request plumbing (csrf_json_post, fetch_csrf_token, json_body,
# clear_body_headers) comes from support/auth_request_helper.rb, and subject
# seeding (seed_existing_account, seed_account_with_password) from
# support/account_seed_helper.rb — both included here explicitly so this helper
# stands on its own, not on the config-level auto-include.
#
# =============================================================================

ENV['AUTH_MFA_ENABLED'] = 'true'

require 'rotp'

module MfaFlowHelper
  def self.included(base)
    base.include Rack::Test::Methods
    base.include AuthRequestHelper
    base.include AccountSeedHelper

    # Hard-fail (not skip): this lane EXISTS to cover the MFA path, so a boot
    # without the OTP feature is harness breakage, not an environment quirk.
    base.before(:all) do
      otp_loaded = Auth::Config.method_defined?(:otp_auth_route) ||
                   Auth::Config.private_method_defined?(:otp_auth_route)
      unless otp_loaded
        raise 'Rodauth OTP feature not loaded — this suite must boot with ' \
              'AUTH_MFA_ENABLED=true in a fresh process (run via ' \
              '`bundle exec rake spec:integration:full:mfa`; Auth::Config is one-shot)'
      end
    end

    base.let(:identities) { auth_db[:account_identities] }
  end

  def app
    Onetime::Application::Registry.generate_rack_url_map
  end

  # ==========================================================================
  # OTP provisioning — through Rodauth's OWN JSON setup flow, exactly as the
  # SPA does it, so the stored key shape (HMAC) matches production:
  #   phase 1: POST /auth/otp-setup {}            -> 422 + { otp_setup (the
  #            HMAC'd key the authenticator uses), otp_raw_secret }
  #   phase 2: POST /auth/otp-setup {otp_setup, otp_raw_secret, otp_code,
  #            password}                          -> 200, recovery codes added
  # Returns [authenticator secret (the otp_setup value), recovery codes] —
  # auto_add_recovery_codes? is on, and the app's after hook surfaces the
  # generated codes in the phase-2 JSON response (hooks/mfa.rb).
  #
  # Clears cookies on the way out: the flow under test must start from an
  # UNAUTHENTICATED browser, like a user on a fresh device.
  # ==========================================================================

  def provision_totp(email, password: AuthTestConstants::TEST_PASSWORD)
    csrf_json_post('/auth/login', login: email, password: password)
    expect(last_response.status).to eq(200),
      "Precondition failed: password login for OTP setup (#{last_response.status}: #{last_response.body})"

    csrf_json_post('/auth/otp-setup', {})
    expect(last_response.status).to eq(422),
      "Phase-1 otp-setup should return the generated secret with a field error (#{last_response.status}: #{last_response.body})"
    setup_body = json_body
    secret     = setup_body['otp_setup']
    raw_secret = setup_body['otp_raw_secret']
    expect(secret).not_to be_nil
    expect(raw_secret).not_to be_nil

    csrf_json_post(
      '/auth/otp-setup',
      otp_setup: secret,
      otp_raw_secret: raw_secret,
      otp_code: ROTP::TOTP.new(secret).now,
      password: password,
    )
    expect(last_response.status).to eq(200),
      "Phase-2 otp-setup should confirm the secret (#{last_response.status}: #{last_response.body})"
    recovery_codes = Array(json_body['recovery_codes'])

    clear_cookies
    [secret, recovery_codes]
  end

  # Rodauth's OTP reuse guard (otp_update_last_use) rejects any code within one
  # interval (30s) of last_use — and setup just stamped last_use=now. Rewind it
  # so the auth step can accept a fresh code immediately instead of sleeping
  # out the window in the test.
  #
  # One rewind covers a failed-then-retry sequence: Rodauth stamps last_use
  # only on SUCCESSFUL validation (`otp_valid_code? && otp_update_last_use`
  # short-circuits), so a rejected code leaves the rewound value in place and
  # the subsequent good code is still accepted without a second rewind.
  def allow_immediate_otp_reuse!(account_id)
    auth_db[:account_otp_keys].where(id: account_id).update(last_use: Time.now - 300)
  end

  # A code guaranteed to be rejected RIGHT NOW: Rodauth validates with
  # otp_drift (30s), so the previous and next interval's codes are accepted
  # too — a candidate must differ from all three, not just the current code.
  # Counter-based so every candidate stays six digits by construction (at most
  # four iterations: the valid set has exactly three elements).
  def wrong_otp_code(secret)
    totp  = ROTP::TOTP.new(secret)
    now   = Time.now.to_i
    valid = [totp.at(now - 30), totp.at(now), totp.at(now + 30)]
    (0..valid.size).each do |i|
      candidate = i.to_s.rjust(6, '0')
      return candidate unless valid.include?(candidate)
    end
  end
end

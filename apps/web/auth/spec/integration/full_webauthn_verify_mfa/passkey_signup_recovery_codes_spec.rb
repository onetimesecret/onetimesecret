# apps/web/auth/spec/integration/full_webauthn_verify_mfa/passkey_signup_recovery_codes_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode, passkey signup lane, MFA on)
# =============================================================================
#
# OPEN DEFECT, kept reproducible: passkey signup verification fails while
# Rodauth's recovery_codes feature is loaded (AUTH_MFA_ENABLED=true together
# with AUTH_WEBAUTHN_VERIFY_ACCOUNT=true).
#
# Inside the verify transaction, webauthn_verify_account's
# before_verify_account adds the new passkey with add_webauthn_credential.
# recovery_codes overrides that method to add the account's missing codes
# (auto_add_recovery_codes? is on in config/features/mfa.rb), and
# add_recovery_code inserts under session_value, which is nil until the
# autologin after the transaction. The insert fails
# (NOT NULL constraint failed: account_recovery_codes.id), the request answers
# 500 and the transaction rolls back: verify_account, clear_tokens and the
# app's after_verify_account hook never run. Unchanged in rodauth 2.48.0.
#
# The example asserts the defect itself, then marks itself pending:
#   - before the `pending` call, failures are real: the boot, the signup, the
#     ceremony's first phase, and the second phase's answer, which must be
#     this 500 from this insert. A different failure is reported as a
#     failure, not as pending;
#   - after it, the expected behaviour is asserted. It is reached only in the
#     known-defect state, where its first assertion fails, so RSpec reports
#     the example as pending;
#   - once the defect is fixed the second phase answers 200 and the 500
#     expectation fails the example. The fix deletes the known-defect
#     expectations and the `pending` line, turning this into its regression
#     spec.
# No :aggregate_failures: it defers every failure, the pre-pending ones too,
# to the end of the example, where `pending` would absorb them.
#
# Own process: the full-webauthn-verify lane's task runs this directory
# separately, with AUTH_MFA_ENABLED=true (lib/tasks/spec.rake
# full:webauthn_verify). The lane env file says false, for the other
# directory's --only runs, so this file sets the variable at load time, as
# support/mfa_flow_helper.rb does. RSpec loads every file before any hook
# boots the app; loaded beside integration/full_webauthn_verify/ it would turn
# MFA on there too, which that directory's first example refuses.
#
# RUN:
#   tests/lanes/run full-webauthn-verify
#   tests/lanes/run full-webauthn-verify \
#     --only apps/web/auth/spec/integration/full_webauthn_verify_mfa/passkey_signup_recovery_codes_spec.rb
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/domains_enabled_context'
require_relative '../../support/passkey_signup_helper'

if defined?(Onetime) && Onetime.respond_to?(:ready?) && Onetime.ready?
  raise 'passkey_signup_recovery_codes_spec loaded after the app booted: AUTH_MFA_ENABLED cannot take effect. ' \
        'Run it through tests/lanes/run full-webauthn-verify (own process).'
end

ENV['AUTH_MFA_ENABLED'] = 'true'

# :full_auth_mode is explicit, as in integration/full_mfa: the directory-derived
# tag (spec/spec_helper.rb) matches only /integration/full/.
RSpec.describe 'Passkey signup verification with recovery codes loaded',
  :full_auth_mode, type: :integration,
  lane_env: { 'AUTH_WEBAUTHN_VERIFY_ACCOUNT' => 'true' } do
  include PasskeySignupHelper

  before(:all) { boot_onetime_app }

  include_context 'domains enabled'

  let(:account_email) { unique_test_email('passkey-signup-mfa') }

  after do
    Onetime::Customer.find_by_email(OT::Utils.normalize_email(account_email))&.destroy!
  rescue StandardError
    nil
  end

  it 'verifies the account and the Customer' do
    expect(Auth::Config.features).to include(:webauthn_verify_account, :verify_account, :recovery_codes)
    expect(Onetime.auth_config.verify_account_enabled?).to be(false)

    account = passkey_signup!(account_email, password: 'PasskeySignupMfa-Password123!', host: canonical_host)
    key     = emailed_verify_key
    options = passkey_setup_options(key, host: canonical_host)

    # The router's error_handler passes every unhandled exception here.
    unhandled = []
    allow(Auth::ErrorTranslator).to receive(:log_entry).and_wrap_original do |original, error|
      unhandled << error
      original.call(error)
    end
    submit_passkey_setup(key, options, host: canonical_host)

    # The known defect, and nothing else.
    expect(last_response.status).to eq(500),
      "expected the known 500, got #{last_response.status}. A 200 means the defect is fixed: delete " \
      'these two expectations and the pending call, as the header of this file says'
    expect(unhandled).to contain_exactly(
      an_instance_of(Sequel::NotNullConstraintViolation)
        .and(having_attributes(message: include('account_recovery_codes.id'))),
    )

    pending 'recovery_codes inserts under a nil session_value during passkey verification (500, NOT NULL ' \
            'constraint on account_recovery_codes.id); see the header of this file'

    expect(last_response.status).to eq(200), "#{last_response.status}: #{last_response.body}"
    expect(auth_db[:accounts].where(id: account[:id]).get(:status_id)).to eq(AuthTestConstants::STATUS_VERIFIED)
    expect(auth_db[:account_webauthn_keys].where(account_id: account[:id]).count).to eq(1)
    expect(verification_key_rows(account[:id])).to eq(0)
    expect(Onetime::Customer.find_by_email(OT::Utils.normalize_email(account_email)).verified?).to be(true)
  end
end

# apps/web/auth/spec/integration/full_webauthn_verify_mfa/passkey_signup_recovery_codes_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode, passkey signup lane, MFA on)
# =============================================================================
#
# Passkey signup verification while Rodauth's recovery_codes feature is loaded
# (AUTH_MFA_ENABLED=true together with AUTH_WEBAUTHN_VERIFY_ACCOUNT=true), in
# the boot production gets: config.rb as shipped, no router subclass and no
# predicate stubs.
#
# Inside the verify transaction, webauthn_verify_account's
# before_verify_account adds the new passkey with add_webauthn_credential.
# recovery_codes overrides that method to add the account's missing codes
# (auto_add_recovery_codes? is on in config/features/mfa.rb). Released
# rodauth (2.45.0 through 2.48.0) inserts them under session_value, which is
# nil until the autologin after the transaction: the insert failed
# (NOT NULL constraint failed: account_recovery_codes.id), the request
# answered 500 and the transaction rolled back, so the account stayed
# unverified. The rodauth fork the Gemfile pins keys the codes on the account
# the verify key loads (onetimesecret/rodauth#3). This example fails if that
# regresses in this boot;
# integration/full_mfa/webauthn_verify_account_recovery_codes_spec.rb covers
# the account scoping against a router subclass.
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

  it 'verifies the account and the Customer and adds the codes to that account', :aggregate_failures do
    expect(Auth::Config.features).to include(:webauthn_verify_account, :verify_account, :recovery_codes)
    expect(Onetime.auth_config.verify_account_enabled?).to be(false)

    account     = passkey_signup!(account_email, password: 'PasskeySignupMfa-Password123!', host: canonical_host)
    key         = emailed_verify_key
    options     = passkey_setup_options(key, host: canonical_host)
    codes_limit = Auth::Config::Features::MFA::RECOVERY_CODES_LIMIT
    rows_before = auth_db[:account_recovery_codes].count

    submit_passkey_setup(key, options, host: canonical_host)

    expect(last_response.status).to eq(200), "#{last_response.status}: #{last_response.body}"
    expect(auth_db[:accounts].where(id: account[:id]).get(:status_id)).to eq(AuthTestConstants::STATUS_VERIFIED)
    expect(auth_db[:account_webauthn_keys].where(account_id: account[:id]).count).to eq(1)
    expect(auth_db[:account_recovery_codes].where(id: account[:id]).count).to eq(codes_limit)
    expect(auth_db[:account_recovery_codes].count - rows_before).to eq(codes_limit)
    expect(verification_key_rows(account[:id])).to eq(0)
    expect(Onetime::Customer.find_by_email(OT::Utils.normalize_email(account_email)).verified?).to be(true)
  end
end

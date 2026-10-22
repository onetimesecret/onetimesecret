# apps/web/auth/spec/integration/full_webauthn_verify/webauthn_verify_account_hook_spec.rb
#
# frozen_string_literal: true

# =============================================================================
# TEST TYPE: Integration (full mode, passkey signup lane)
# =============================================================================
#
# after_verify_account runs when verify_account is loaded through
# webauthn_verify_account alone.
#
# AUTH_WEBAUTHN_VERIFY_ACCOUNT=true enables Rodauth's webauthn_verify_account
# (config/features/webauthn.rb), which depends on verify_account. So with the
# verify_account flag off, POST /auth/verify-account still exists and verifies
# the account. The app's after_verify_account hook (config/hooks/account.rb)
# used to be registered behind that flag alone, so in this configuration the
# SQL account was verified while the Customer stayed unverified and the
# federated claim the signup hook defers to verification never ran. The enable
# call (config/features/account_management.rb), the email template
# (config/email.rb), the hook and the signup deferral now all follow
# Onetime.auth_config.verify_account_loaded?, which counts either path.
#
# The app is the real one: tests/lanes/full-webauthn-verify boots config.rb
# with webauthn and the sub-feature on, verify_account and MFA off
# (MockAuthConfig reads all four from the lane env), so every configure step,
# RestrictTo and LoginRequestEnumeration included, runs as in production. The
# first example pins that boot, since the others would also pass under the
# verify_account flag.
#
# The verification is Rodauth's own two-phase JSON ceremony, driven by
# support/passkey_signup_helper.rb. The same boot with MFA on is the lane's
# second process (integration/full_webauthn_verify_mfa/).
#
# RUN:
#   tests/lanes/run full-webauthn-verify
#   tests/lanes/run full-webauthn-verify \
#     --only apps/web/auth/spec/integration/full_webauthn_verify/webauthn_verify_account_hook_spec.rb
# =============================================================================

require_relative '../../spec_helper'
require_relative '../../support/domains_enabled_context'
require_relative '../../support/passkey_signup_helper'

# :full_auth_mode is explicit, as in integration/full_mfa: the directory-derived
# tag (spec/spec_helper.rb) matches only /integration/full/, and that tag is
# what installs the full-mode suite database and MockAuthConfig before boot.
RSpec.describe 'after_verify_account with verify_account loaded by webauthn_verify_account only',
  :full_auth_mode, type: :integration,
  lane_env: { 'AUTH_WEBAUTHN_VERIFY_ACCOUNT' => 'true' } do
  include PasskeySignupHelper

  before(:all) { boot_onetime_app }

  # The passkey is created for the installed canonical host, the RP ID the
  # server offers there (Auth::PublicHost.webauthn_host), as in the full_mfa
  # passkey specs.
  include_context 'domains enabled'

  let(:password) { 'WebauthnVerify-Password123!' }
  let(:account_email) { unique_test_email('webauthn-verify') }
  let(:normalized_email) { OT::Utils.normalize_email(account_email) }

  before do
    allow(Auth::Operations::EnsureDefaultWorkspace).to receive(:new).and_call_original
    allow(Auth::Operations::EnsureDefaultWorkspace).to receive(:claim_pending_federation_for).and_call_original
  end

  after do
    Onetime::Customer.find_by_email(normalized_email)&.destroy!
  rescue StandardError
    nil
  end

  def customer
    Onetime::Customer.find_by_email(normalized_email)
  end

  def sign_up!
    passkey_signup!(account_email, password: password, host: canonical_host)
  end

  def verify_with_passkey!(key)
    submit_passkey_setup(key, passkey_setup_options(key, host: canonical_host), host: canonical_host)
    expect(last_response.status).to eq(200),
      "Phase-2 verify-account should verify the account (#{last_response.status}: #{last_response.body})"
  end

  it 'boots verify_account through webauthn_verify_account, with the flag and MFA off', :aggregate_failures do
    expect(Onetime.auth_config.verify_account_enabled?).to be(false)
    expect(Onetime.auth_config.verify_account_loaded?).to be(true)
    expect(Auth::Config.features).to include(:webauthn_verify_account, :verify_account)
    expect(Auth::Config.features).not_to include(:recovery_codes)
  end

  it 'verifies the Customer, removes the key row and runs the deferred claim', :aggregate_failures do
    account = sign_up!
    expect(verification_key_rows(account[:id])).to eq(1)
    expect(customer.verified?).to be(false)

    verify_with_passkey!(emailed_verify_key)

    expect(auth_db[:accounts].where(id: account[:id]).get(:status_id)).to eq(AuthTestConstants::STATUS_VERIFIED)
    expect(auth_db[:account_webauthn_keys].where(account_id: account[:id]).count).to eq(1)
    expect(verification_key_rows(account[:id])).to eq(0)

    verified = customer
    expect(verified.verified?).to be(true)
    expect(verified.verified_by).to eq('email')
    expect(Auth::Operations::EnsureDefaultWorkspace).to have_received(:claim_pending_federation_for)
      .with(an_object_having_attributes(extid: verified.extid))

    # What the operator tooling reads: no pending verification for the account.
    diagnosis = Auth::Operations::Customers::Diagnose.new(customer: verified).call
    expect(diagnosis.sections.fetch(:verification)).to include(available: true, pending: false)
  end

  it 'defers the federated claim at signup, as the verify_account flag does', :aggregate_failures do
    sign_up!

    expect(Auth::Operations::EnsureDefaultWorkspace).to have_received(:new)
      .with(hash_including(require_verification: true))
    expect(Auth::Operations::EnsureDefaultWorkspace).not_to have_received(:claim_pending_federation_for)
  end
end

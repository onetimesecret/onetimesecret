# apps/web/auth/spec/support/account_seed_helper.rb
#
# frozen_string_literal: true

require_relative 'auth_test_constants'

# =============================================================================
# Account seeding (auto-included into `type: :integration`)
# =============================================================================
#
# One place to build the SUBJECT of an auth integration spec: an accounts row
# plus its paired Customer, optionally with an Argon2 password hash.
#
# Every field here is load-bearing for the gem's own lookups, which is why the
# copies had drifted apart in wording but never in behaviour (the copy counts
# before this file: seed_account_with_password 4, seed_existing_account 3):
#
#   status_id = Verified  — both satisfies _account_from_login's status filter
#     AND makes open_account? true, so Rodauth skips its verify-account branch.
#   external_id = customer.extid — the accounts row and the Customer are one
#     subject. Flows that probe customer state resolve :unreadable without it
#     (e.g. the SSO mailbox-proof watermark check reads
#     Customer#last_password_update via load_by_extid_or_email).
#   Argon2 cost params — mirror the test config in config/features/argon2.rb.
#
# Auto-included alongside AuthRequestHelper (spec_helper.rb) and included
# explicitly by MfaFlowHelper, so the full_mfa lane does not depend on the
# config-level include. `auth_db` comes from ProductionConfigHelper.
#
# A group that defines either method itself still wins — a `def` in the example
# group body sits below config-included modules in the ancestor chain.
#
# =============================================================================

module AccountSeedHelper
  # Seed a VERIFIED account (accounts row + linked Customer) WITHOUT a
  # password — an SSO-only subject. Returns the account_id.
  def seed_existing_account(email)
    normalized = OT::Utils.normalize_email(email)
    customer   = Onetime::Customer.new(email: normalized)
    customer.save
    auth_db[:accounts].insert(
      email: normalized,
      status_id: AuthTestConstants::STATUS_VERIFIED,
      external_id: customer.extid,
    )
  end

  # Seed a VERIFIED account WITH an Argon2 password hash. Returns the
  # account_id.
  #
  # Two distinct reasons a spec wants the password: to establish a real
  # authenticated session through the login route, and — in the full_mfa lane —
  # as the OTP-PROVISIONING VEHICLE, because this deploy sets
  # two_factor_modifications_require_password? and Rodauth's real setup flow is
  # the only way to get a production-shaped (HMAC'd) OTP key. Specs whose
  # subject is passwordless in production still seed it for that second reason;
  # see their headers.
  def seed_account_with_password(email, password: AuthTestConstants::TEST_PASSWORD)
    account_id = seed_existing_account(email)
    require 'argon2'
    hasher = Argon2::Password.new(t_cost: 1, m_cost: 5, p_cost: 1)
    auth_db[:account_password_hashes].insert(id: account_id, password_hash: hasher.create(password))
    account_id
  end
end

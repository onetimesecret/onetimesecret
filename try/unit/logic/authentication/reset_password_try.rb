# try/unit/logic/authentication/reset_password_try.rb
#
# frozen_string_literal: true

# Tests for the simple-mode ResetPassword logic class: token validation, the
# passphrase change itself, and the M-2 session-revocation sequence (watermark
# stamp + revoke ALL) that this path enforces itself because the Rodauth
# after_reset_password hook never fires in simple mode. The user arrives here
# from an email link (unauthenticated), so unlike UpdatePassword there is no
# current session to preserve.

require_relative '../../../support/test_logic'

# Full boot (connect_to_db) so configure_familia runs: creating Secrets mints
# verifiable identifiers, which need VERIFIABLE_ID_HMAC_SECRET — derived from
# IDENTIFIER_SECRET/config by that initializer, which `OT.boot! :test, false`
# would skip (same reason the revoke-op tryout boots this way).
OT.boot! :test

require 'securerandom'
require 'onetime/operations/sessions/track_metadata'

@db           = Familia.dbclient
@codec        = Onetime::SessionCodec.from_config
@new_password = 'n3wP4ssw0rd'

# A verified customer with a pending reset secret, created the same way
# ResetPasswordRequest#process does.
@cust = Onetime::Customer.create!(email: generate_random_email)
@cust.update_passphrase 'oldp4ssw0rd'
@cust.verified = 'true'
@cust.save

@secret                    = Onetime::Secret.create!(owner_id: @cust.objid)
@secret.default_expiration = 86_400 # 24h, as ResetPasswordRequest sets it
@secret.verification       = 'true'
@secret.save
@cust.reset_secret         = @secret.identifier

# A live tracked session for the customer — the stolen/pre-reset session that
# MUST NOT survive the reset.
@stolen_sid = SecureRandom.hex(32)
Onetime::Operations::Sessions::TrackMetadata.new(
  session_id: @stolen_sid,
  session_data: { 'authenticated' => true, 'external_id' => @cust.extid,
                  'ip_address' => '203.0.113.9', 'user_agent' => 'UA' },
).call
@db.set("session:#{@stolen_sid}", @codec.encode({ 'authenticated' => true,
                                                  'external_id' => @cust.extid,
                                                  'email' => @cust.email }))

# TRYOUTS

## The pre-reset session blob exists before the reset
@db.get("session:#{@stolen_sid}").nil?
#=> false

## Reset with a valid token succeeds and changes the passphrase
# The resetting browser still holds authenticated session data (reset
# requested while signed in) — the reset must clear it, or session commit
# could write the just-revoked session straight back.
@reset_sess = { 'authenticated' => true, 'external_id' => @cust.extid }
strategy_result = MockStrategyResult.new(session: @reset_sess, user: nil)
params = {
  'key' => @secret.identifier,
  'password' => @new_password,
  'password-confirm' => @new_password,
}
logic = AccountAPI::Logic::Authentication::ResetPassword.new strategy_result, params
logic.raise_concerns
logic.process
Onetime::Customer.load(@cust.objid).passphrase?(@new_password)
#=> true

## M-2: the resetting browser's own in-memory session is cleared
@reset_sess.empty?
#=> true

## M-2: the pre-reset session blob is revoked by the reset
@db.get("session:#{@stolen_sid}").nil?
#=> true

## M-2: the revoked sid is dropped from the active-sessions index
Onetime::Customer.load(@cust.objid).active_sessions.revrange(0, -1).include?(@stolen_sid)
#=> false

## M-2: the reset stamps the credential watermark (Customer#last_password_update),
## so even an unreached blob is retired by the auth-time `<=` check
Onetime::Customer.load(@cust.objid).last_password_update.to_i.positive?
#=> true

## An invalid (already-consumed) token cannot reset again
strategy_result = MockStrategyResult.anonymous
params = {
  'key' => @secret.identifier,
  'password' => 'an0therPw!',
  'password-confirm' => 'an0therPw!',
}
logic = AccountAPI::Logic::Authentication::ResetPassword.new strategy_result, params
begin
  logic.raise_concerns
  logic.process
rescue => e
  e.class
end
#=> Onetime::MissingSecret

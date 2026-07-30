# try/unit/logic/account/update_password_try.rb
#
# frozen_string_literal: true

# Tests for UpdatePassword logic in simple auth mode (Redis passphrase).
# Covers password validation, verification, the change flow, and the M-2
# session-revocation sequence (watermark stamp + revoke-except-current) that
# the simple-mode path enforces itself because the Rodauth
# after_change_password hook never fires in simple mode.

require_relative '../../../support/test_logic'

OT.boot! :test, false

require 'securerandom'
require 'onetime/operations/sessions/track_metadata'
require 'onetime/operations/sessions/store'

@email_address = generate_random_email
@current_password = 'oldp4ssw0rd'
@new_password = 'n3wP4ssw0rd'
@session = {}
@cust = Onetime::Customer.new email: @email_address
@cust.update_passphrase @current_password
@strategy_result = MockStrategyResult.new(session: @session, user: @cust)

# TRYOUTS

## Can create UpdatePassword instance
params = {
  'password' => @current_password,
  'newpassword' => @new_password,
  'password-confirm' => @new_password
}
obj = AccountAPI::Logic::Account::UpdatePassword.new @strategy_result, params
obj.class.name
#=> 'AccountAPI::Logic::Account::UpdatePassword'

## Raises error when current password is empty
params = { 'password' => '', 'newpassword' => @new_password, 'password-confirm' => @new_password }
obj = AccountAPI::Logic::Account::UpdatePassword.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Current password is required']

## Raises error when current password is incorrect
params = { 'password' => 'wrongpassword', 'newpassword' => @new_password, 'password-confirm' => @new_password }
obj = AccountAPI::Logic::Account::UpdatePassword.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'Current password is incorrect']

## Raises error when new password matches current
params = { 'password' => @current_password, 'newpassword' => @current_password, 'password-confirm' => @current_password }
obj = AccountAPI::Logic::Account::UpdatePassword.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'New password cannot be the same as current password']

## Raises error when new password is too short
params = { 'password' => @current_password, 'newpassword' => 'ab', 'password-confirm' => 'ab' }
obj = AccountAPI::Logic::Account::UpdatePassword.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'New password is too short']

## Raises error when password confirmation does not match
params = { 'password' => @current_password, 'newpassword' => @new_password, 'password-confirm' => 'mismatch' }
obj = AccountAPI::Logic::Account::UpdatePassword.new @strategy_result, params
begin
  obj.raise_concerns
rescue => e
  [e.class, e.message]
end
#=> [Onetime::FormError, 'New passwords do not match']

## No errors raised with valid params
cust = Onetime::Customer.new email: generate_random_email
cust.update_passphrase @current_password
strategy_result = MockStrategyResult.new(session: @session, user: cust)
params = { 'password' => @current_password, 'newpassword' => @new_password, 'password-confirm' => @new_password }
obj = AccountAPI::Logic::Account::UpdatePassword.new strategy_result, params
obj.raise_concerns
#=> nil

## Process changes the password successfully (asserted on a RELOADED customer,
## so the check proves persistence rather than re-reading the mutated instance)
@change_cust = Onetime::Customer.create!(email: generate_random_email)
@change_cust.update_passphrase @current_password
strategy_result = MockStrategyResult.new(session: @session, user: @change_cust)
params = { 'password' => @current_password, 'newpassword' => @new_password, 'password-confirm' => @new_password }
obj = AccountAPI::Logic::Account::UpdatePassword.new strategy_result, params
obj.raise_concerns
obj.process
Onetime::Customer.load(@change_cust.objid).passphrase?(@new_password)
#=> true

## Old password no longer works after change
@change_cust.passphrase?(@current_password)
#=> false

## M-2: simple-mode change revokes the OTHER session blob and keeps the current one
@db    = Familia.dbclient
@codec = Onetime::SessionCodec.from_config
@m2_cust = Onetime::Customer.create!(email: generate_random_email)
@m2_cust.update_passphrase @current_password
@current_sid = SecureRandom.hex(32)
@other_sid   = SecureRandom.hex(32)
[@current_sid, @other_sid].each do |sid|
  Onetime::Operations::Sessions::TrackMetadata.new(
    session_id: sid,
    session_data: { 'authenticated' => true, 'external_id' => @m2_cust.extid,
                    'ip_address' => '203.0.113.9', 'user_agent' => 'UA' },
  ).call
  @db.set("session:#{sid}", @codec.encode({ 'authenticated' => true,
                                            'external_id' => @m2_cust.extid,
                                            'email' => @m2_cust.email }))
end
# Rack-shaped session: responds to #id with an object exposing #public_id
# (so the logic can resolve the sid to preserve) and to #options (so the
# rotation lever is available, like a live rack-session SessionHash).
@m2_sess = {}
m2_sid_obj  = Struct.new(:public_id).new(@current_sid)
@m2_options = {}
@m2_sess.define_singleton_method(:id) { m2_sid_obj }
m2_options = @m2_options
@m2_sess.define_singleton_method(:options) { m2_options }
strategy_result = MockStrategyResult.new(session: @m2_sess, user: @m2_cust)
params = { 'password' => @current_password, 'newpassword' => @new_password, 'password-confirm' => @new_password }
obj = AccountAPI::Logic::Account::UpdatePassword.new strategy_result, params
obj.raise_concerns
obj.process
[@db.get("session:#{@other_sid}").nil?, @db.get("session:#{@current_sid}").nil?]
#=> [true, false]

## M-2: the change stamps the credential watermark (Customer#last_password_update)
@m2_watermark = Onetime::Customer.load(@m2_cust.objid).last_password_update.to_i
@m2_watermark.positive?
#=> true

## M-2: the kept session is re-stamped STRICTLY past the watermark, so the
## auth-time `<=` check and the watermark-honoring async sweep both spare it
@m2_sess['authenticated_at'].to_i > @m2_watermark
#=> true

## M-2: session-id rotation is requested (fixation defense) — Rack's commit
## path will delete the pre-change sid's blob and re-persist under a fresh sid
@m2_options[:renew]
#=> true

## M-2: both old sids are dropped from the index — the revoked one by the
## revoke op, the pre-rotation current one by the rotation tidy (the NEW sid
## is re-tracked at session commit, which a unit test doesn't perform)
@m2_cust.active_sessions.revrange(0, -1)
#=> []

## M-2: with no resolvable current sid, ALL sessions are revoked (fail secure)
@ns_cust = Onetime::Customer.create!(email: generate_random_email)
@ns_cust.update_passphrase @current_password
@ns_sid = SecureRandom.hex(32)
Onetime::Operations::Sessions::TrackMetadata.new(
  session_id: @ns_sid,
  session_data: { 'authenticated' => true, 'external_id' => @ns_cust.extid,
                  'ip_address' => '203.0.113.9', 'user_agent' => 'UA' },
).call
@db.set("session:#{@ns_sid}", @codec.encode({ 'authenticated' => true,
                                              'external_id' => @ns_cust.extid,
                                              'email' => @ns_cust.email }))
strategy_result = MockStrategyResult.new(session: {}, user: @ns_cust)
params = { 'password' => @current_password, 'newpassword' => @new_password, 'password-confirm' => @new_password }
obj = AccountAPI::Logic::Account::UpdatePassword.new strategy_result, params
obj.raise_concerns
obj.process
@db.get("session:#{@ns_sid}").nil?
#=> true

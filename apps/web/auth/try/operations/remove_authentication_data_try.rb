# apps/web/auth/try/operations/remove_authentication_data_try.rb
#
# frozen_string_literal: true

# RemoveAuthenticationData: the Redis session sweep (#3858).
#
# delete_redis_sessions SCANs session:* for blobs whose codec-DECODED
# external_id matches the closing account, deletes each matching blob AND
# purges its per-value sidecar keys, skipping sidecar-shaped keys. Sessions are
# AES-256-GCM encrypted, so the sweep MUST decode through the codec -- the old
# JSON.parse(base64) path raised on every authenticated blob and silently
# skipped it, leaving live sessions behind on account closure. These cases
# assert the real Redis effects (the method swallows all errors, so nothing
# else could catch a regression). Redis-only: no auth DB required (db: passed
# non-nil to skip the connect), so they run in the unit lane.
#
# The auth-DATABASE half of the operation (account row and dependent tables,
# missing/empty extid, a non-existent account) is covered in full mode, where
# a database always exists: spec/integration/full/hooks/account_deletion_spec.rb.
# It used to live here behind a wrapper that returned each case's expected
# value when no database was reachable, which is every run of the unit lane,
# so those cases reported passes without executing.
require 'onetime/session/codec'
require 'onetime/session/sidecar'

ENV['RACK_ENV'] = 'test'

require_relative '../../../../../try/support/test_helpers'

require 'onetime'

OT.boot! :test, false

require 'auth/database'
require_relative '../../operations/remove_authentication_data'

## an authenticated, AES-GCM-encrypted session blob for the closing account is
## deleted along with its sidecar keys, while a DIFFERENT account's blob
## survives -- proving the encrypted blob actually decodes (a plain JSON.parse
## skipped every authenticated session)
# Plant blobs with the middleware writer's own secret resolution
# (session_config['secret'], the chain middleware_stack mounts the session
# with) — the sweep's SessionCodec.from_config must resolve the SAME secret
# for the encrypted blob to decode and match.
@ca_secret     = Onetime.session_config['secret']
@ca_codec      = Onetime::SessionCodec.new(@ca_secret)
@ca_db         = Familia.dbclient
@ca_extid      = "extid_close_#{SecureRandom.hex(6)}"
@ca_sid        = SecureRandom.hex(32) # 64 hex -- the shape the sidecar purge is gated on
@ca_blob       = "session:#{@ca_sid}"
@ca_mfa        = "sidecar:#{@ca_sid}:awaiting_mfa"
@ca_other_sid  = SecureRandom.hex(32)
@ca_other_blob = "session:#{@ca_other_sid}"
@ca_op         = Auth::Operations::RemoveAuthenticationData.new(extid: @ca_extid, db: :redis_only)
@ca_db.set(@ca_blob, @ca_codec.encode({ 'external_id' => @ca_extid, 'authenticated' => true }), ex: 3600)
Onetime::SessionSidecar.write(@ca_sid, 'awaiting_mfa', true, codec: @ca_codec)
@ca_db.set(@ca_other_blob, @ca_codec.encode({ 'external_id' => 'someone_else', 'authenticated' => true }), ex: 3600)
@ca_op.send(:delete_redis_sessions, @ca_extid)
[@ca_db.exists(@ca_blob), @ca_db.exists(@ca_mfa), @ca_db.exists(@ca_other_blob)]
#=> [0, 0, 1]

## the sweep reports the count of blobs it deleted (one matching account)
@ca_db.set(@ca_blob, @ca_codec.encode({ 'external_id' => @ca_extid }), ex: 3600)
@ca_result = @ca_op.send(:delete_redis_sessions, @ca_extid)
@ca_db.del(@ca_blob, @ca_other_blob)
Onetime::SessionSidecar.purge(@ca_sid)
@ca_result
#=> 1

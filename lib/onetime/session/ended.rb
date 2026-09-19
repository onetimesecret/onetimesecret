# lib/onetime/session/ended.rb
#
# frozen_string_literal: true

require 'openssl'
require 'familia'

module Onetime
  # A short-lived marker that a session id was ended on purpose
  # (RISK-2026-09-19-01).
  #
  # The session store is last-writer-wins and every response re-sends the
  # session cookie. A request that loaded a session BEFORE it was ended
  # (logout, revocation, an id renewal) and commits AFTER writes the whole
  # blob back under the old id and hands the browser the old cookie again. In
  # full auth mode the missing active-session row makes that copy refusable
  # ({Onetime::ActiveSessionGate.end_session}). Simple mode has no row, and
  # neither has an anonymous or pre-#4452 session in full mode: there the copy
  # was a complete, valid session, and the logout was undone.
  #
  # Every path that deletes a session blob calls {.mark} FIRST, and
  # {Onetime::Session#write_session} asks {.ended?} AFTER its own SET, taking
  # the blob back out when the answer is yes. The two orders together leave no
  # interleaving in which the blob survives:
  #
  #     ender:   SET marker  ->  DEL blob
  #     writer:  SET blob    ->  EXISTS marker  (-> DEL blob)
  #
  # If the writer's EXISTS misses the marker, the marker was set after it, so
  # the ender's DEL runs after the writer's SET. If it sees the marker, the
  # writer removes its own copy. A check BEFORE the write could not give this:
  # the ender could run whole between the check and the SET.
  #
  # ## The key
  #
  # `ended_sid:<HMAC-SHA256(global secret, "session-ended:v1:<sid>")>`
  #
  # - A keyed digest, never the sid. The sid is a bearer credential whose only
  #   server-side copies are the blob and sidecar key NAMES, all of which the
  #   ender deletes; the marker must not keep a copy alive where they are
  #   gone. Its own domain string, so it equals neither the colonel revoke
  #   handle ({Onetime::SessionMetadata.handle_for}) nor the snapshot epoch
  #   ({Onetime::SnapshotOrdering.epoch_for}), which is published to the tab.
  # - The full 256 bits: a collision would refuse an unrelated session's
  #   write.
  # - The prefix must never contain "session":
  #   {Onetime::Operations::Sessions::Store::SESSION_SCAN_PATTERN} matches
  #   `*session*` string keys and would list the marker as a session.
  #
  # ## The lifetime
  #
  # The marker only has to outlive requests that were already in flight when
  # the session ended: only they hold the ended session's data. The store
  # never issues the id again (256 random bits), and a cookie still naming it
  # finds no blob and loads an empty session (under a new id while the marker
  # lives, see Onetime::Session#find_session), so a later write under it
  # carries nothing of the ended session. {TTL} is five times Puma's 60 s
  # worker timeout (etc/puma.rb), the longest a request can run before its
  # worker is killed.
  # It is deliberately NOT the session lifetime: a marker per ended session
  # for 24 hours or more would be the keyspace the blob delete just freed.
  module SessionEnded
    extend self

    KEY_PREFIX = 'ended_sid'
    DOMAIN     = 'session-ended:v1'
    TTL        = 300

    # @param sid [String, #public_id, nil] the plain session id
    # @return [String, nil] the marker key, nil for a blank id
    def key_for(sid)
      plain = sid.respond_to?(:public_id) ? sid.public_id : sid
      plain = plain.to_s
      return nil if plain.empty?

      digest = OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha256'), OT.global_secret.to_s, "#{DOMAIN}:#{plain}")
      Familia.join(KEY_PREFIX, digest)
    end

    # Record that `sid` was ended. Call it BEFORE deleting the blob.
    #
    # Never raises: ending the session matters more than the marker, and a
    # caller that could not set it is exactly where it was before this
    # existed. The failure is logged with the handle, never the sid.
    #
    # @return [Boolean] true when the marker was written
    def mark(sid, dbclient: nil)
      key = key_for(sid)
      return false if key.nil?

      (dbclient || Familia.dbclient).set(key, '1', ex: TTL)
      true
    rescue StandardError => ex
      OT.lw "[session_ended] marker could not be written (session_handle=#{handle(sid)}): #{ex.class}: #{ex.message}"
      false
    end

    # One EXISTS. Raises on a datastore error: the caller is the session
    # write, whose own rescue reports the write as failed, and a write that
    # cannot be checked must not be reported as saved.
    #
    # @return [Boolean]
    def ended?(sid, dbclient: nil)
      key = key_for(sid)
      return false if key.nil?

      reply = (dbclient || Familia.dbclient).exists(key)
      reply == true || (reply.is_a?(Integer) && reply.positive?)
    end

    private

    def handle(sid)
      plain = sid.respond_to?(:public_id) ? sid.public_id : sid
      Onetime::SessionMetadata.handle_for(plain)
    rescue StandardError
      nil
    end
  end
end

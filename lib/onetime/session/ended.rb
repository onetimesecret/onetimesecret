# lib/onetime/session/ended.rb
#
# frozen_string_literal: true

require 'openssl'
require 'familia'

require_relative '../session'

module Onetime
  # Short-lived tombstone for an intentionally ended session ID. It prevents
  # an in-flight request from restoring the old blob after logout or renewal,
  # including sessions with no Rodauth active-session row.
  #
  # Mark before deleting the blob. Writers check after SET and delete their
  # copy if marked. If the writer misses the marker, the ender's DEL follows
  # the writer's SET. Checking only before SET would leave a race.
  #
  # Use a full, domain-separated HMAC, never the bearer ID. Keep `session`
  # out of the prefix so the admin session scan does not list tombstones.
  # {TTL} must outlast potentially delayed writes, not the session itself.
  # Puma's worker timeout is not a request deadline.
  module Session::Ended
    extend self

    KEY_PREFIX = 'ended_sid'
    DOMAIN     = 'session-ended:v1'
    TTL        = 3600

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

    # Log-safe identifier for a sid: the same keyed digest the colonel
    # session view shows. Public so callers that must LOG a refused blob
    # delete (see {Onetime::Operations::Sessions::Store.destroy_blob}) have
    # one canonical, sid-safe handle helper and don't reimplement it.
    #
    # @param sid [String, Rack::Session::SessionId, nil]
    # @return [String, nil]
    def handle_for(sid)
      plain = sid.respond_to?(:public_id) ? sid.public_id : sid
      Onetime::SessionMetadata.handle_for(plain)
    rescue StandardError
      nil
    end

    private

    def handle(sid)
      handle_for(sid)
    end
  end
end

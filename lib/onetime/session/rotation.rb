# lib/onetime/session/rotation.rb
#
# frozen_string_literal: true

require_relative 'ended'
require_relative 'sidecar'

module Onetime
  # Session-id rotation at a privilege transition (#4466).
  #
  # Issues a new session id for a session that stays signed in, and ends the
  # old id the way a logout ends it. The password step already gets this from
  # Rodauth: `login_session` calls the app's `clear_session`, which is
  # `session.destroy` (apps/web/auth/config/base.rb), and Rodauth then fills
  # the empty session again. This module is the same step for a session whose
  # data must SURVIVE: the second factor completing (RISK-2026-09-19-02), and
  # the other establishment paths #4466 lists once they call it.
  #
  # ## The mechanism
  #
  # Rack's `SessionHash#destroy` is `clear` followed by
  # `@id = store.delete_session(req, @id, options)`. On this store
  # ({Onetime::Session#delete_session}) that one call:
  #
  # - writes the {Onetime::SessionEnded} marker for the old id, so a request
  #   that loaded the old session before this and commits after it cannot
  #   write it back ({Onetime::Session#write_session} refuses the write);
  # - deletes the old blob, or refuses to when the marker could not be
  #   written (the blob must never outlive a missing marker);
  # - purges every sidecar key of the old id and destroys its
  #   {Onetime::SessionMetadata} record;
  # - returns a fresh id, which the session hash adopts at once.
  #
  # {rotate!} copies the session data out before the destroy and writes it
  # back after, so the request's commit persists the same data under the new
  # id, and the response sets the cookie to the new id. Both happen in this
  # request; nothing waits for a later one.
  #
  # ## What crosses the rotation, and what does not
  #
  # Carried, because it is in the session hash: every key the caller has
  # written or left there. That includes Rodauth's `account_id` and
  # `authenticated_by`, the active-session token and its join key
  # (`active_session_id_hmac`, config/features/active_sessions.rb): the row
  # in `account_active_session_keys` is keyed by that digest, not by the Rack
  # id, so the row survives untouched. The surface marker
  # ({Onetime::SessionSurface::KEY}) and the CSRF token are carried too. A
  # caller that wants any of these cleared deletes them itself, before or
  # after the call; this module does not decide for it.
  #
  # Not carried, by design:
  #
  # - The old id's sidecar keys. Explicit-use fields are hand-off state bound
  #   to one id (the SSO connect intent, the pending SSO bind, the reauth
  #   challenge, the recent-reauth proof); a caller consumes them before
  #   rotating or records them afresh after. Externalized fields
  #   (`awaiting_mfa`, `elevated_until`, `domain_context`) were merged into
  #   the hash on the read and are re-externalized under the new id by the
  #   commit, so their VALUES do cross; only the old keys go.
  # - The snapshot version counter. ADR-046 scopes the epoch to one session
  #   id: "A session-ID renewal starts a new epoch instead of attempting to
  #   migrate or compare the old sidecar counter." The epoch is derived from
  #   the id on every request ({Onetime::SnapshotOrdering.epoch_for}) and is
  #   cached nowhere, so the next snapshot carries the new one.
  # - The old {Onetime::SessionMetadata} record and the old id's entry in the
  #   customer's `active_sessions` index. The commit recreates both for the
  #   new id (Onetime::Operations::Sessions::TrackMetadata).
  #
  # ## The `completed:` fields
  #
  # The store's destroy logs a warning when a `destroy_warn` sidecar field
  # still holds a truthy value, its tripwire for a hand-off stranded by a
  # re-key (lib/onetime/session/sidecar.rb). A caller rotating at the END of
  # a hand-off names the fields it has completed; they are deleted on the old
  # id first, so the warning keeps meaning what it says.
  #
  # ## Failure posture: the old id is ended, or nothing changes
  #
  # The one state this must never leave behind is an old blob that is still
  # readable but no longer carries its hand-off fields: for the MFA case that
  # would be a Rodauth-logged-in session without `awaiting_mfa`, which the
  # /auth router serves as an autologin session (Auth::SessionRecheck,
  # router.rb `:not_authenticated`). The store's destroy can produce exactly
  # that when the {Onetime::SessionEnded} marker write fails: it keeps the
  # blob but still purges the sidecar keys. So:
  #
  # 1. The marker is written HERE, before anything else. If that fails,
  #    nothing has been touched and {rotate!} returns an incomplete result:
  #    the old session is exactly as it was, hand-off fields included.
  # 2. Only then are the completed fields deleted and the destroy run. The
  #    store's own marker write is the same SET again.
  # 3. Afterwards the old id must be both marked and without a blob. A blob
  #    that survived is deleted once more directly
  #    ({Onetime::Operations::Sessions::Store.destroy_blob}); if it still
  #    survives, the completed fields are written back onto the old id with
  #    the values they had, so the surviving blob is in the state it was in
  #    (for MFA: still pending), and the result is incomplete.
  #
  # An incomplete result means the caller must not continue on the session:
  # {Onetime::SessionRotation::Incomplete} is what it raises after clearing
  # the session hash (the MFA hook does this; the request then fails and the
  # cleared hash is what the commit writes). A session that is not a Rack
  # session-store session (a bare Hash, as in internal requests and some
  # specs) has no server-side id to rotate and nothing to leave behind;
  # {rotate!} returns nil for it, which is not an incomplete rotation.
  #
  # The data is written back to the hash whatever the destroy did, so a
  # failed rotation never empties a session by itself; the caller decides.
  module SessionRotation
    extend self

    # Raised by a caller that refuses to continue on an unrotated session.
    class Incomplete < StandardError; end

    Result = Struct.new(:old_sid, :new_sid, :complete, :reason, keyword_init: true) do
      def rotated?
        !old_sid.nil? && !new_sid.nil? && old_sid != new_sid
      end
    end

    # @param session [Rack::Session::Abstract::SessionHash] the request's session
    # @param completed [Array<String>] sidecar fields whose hand-off this
    #   rotation completes (deleted on the old id before the destroy)
    # @param dbclient [Object, nil] Redis client override (test seam)
    # @return [Result, nil] nil when the session cannot be rotated
    def rotate!(session, completed: [], dbclient: nil)
      unless rotatable?(session)
        OT.le "[session_rotation] session not rotated: #{session.class} is not a Rack session-store session"
        return nil
      end

      db      = dbclient || Familia.dbclient
      old_sid = plain_id(session.id)
      data    = session.to_hash

      # Step 1: end the old id before touching anything. A marker that cannot
      # be written means the old session stays exactly as it is.
      unless old_sid && SessionEnded.mark(old_sid, dbclient: db)
        OT.le "[session_rotation] session not rotated: ended marker could not be written " \
              "(session_handle=#{handle(old_sid)})"
        return Result.new(old_sid: old_sid, new_sid: old_sid, complete: false, reason: :marker_not_written)
      end

      # Step 2: the completed hand-off fields, remembered so they can be put
      # back if the old blob turns out to survive.
      completed_values = take_completed_fields(old_sid, Array(completed), db)

      begin
        session.destroy
      ensure
        # Whatever the destroy did, the signed-in data goes back into the
        # hash: under the new id normally, under the old one if the destroy
        # raised before re-keying (then nothing was rotated, and the caller
        # reads that off the result).
        session.update(data)
      end

      new_sid = plain_id(session.id)
      result  = Result.new(old_sid: old_sid, new_sid: new_sid, complete: false, reason: nil)

      # Step 3: the old id must be marked and its blob gone.
      if !result.rotated?
        result.reason = :not_rekeyed
      elsif !old_ended?(old_sid, db)
        result.reason = :marker_not_confirmed
      elsif old_blob_survived?(old_sid, db)
        result.reason = :blob_survived
      else
        result.complete = true
      end

      if result.complete
        forget_old_index_entry(data['external_id'], old_sid)
      else
        restore_completed_fields(old_sid, completed_values, db)
      end

      OT.li "[session_rotation] session id rotation #{result.complete ? 'complete' : "incomplete (#{result.reason})"} " \
            "(previous_session_handle=#{handle(old_sid)} session_handle=#{handle(new_sid)})"
      result
    end

    # A Rack session-store session: it can destroy itself through the store,
    # report its id, and take its data back.
    def rotatable?(session)
      %i[destroy to_hash update id].all? { |m| session.respond_to?(m) }
    end

    private

    def plain_id(id)
      value = id.respond_to?(:public_id) ? id.public_id : id
      value = value.to_s
      value.empty? ? nil : value
    end

    # Read then delete each completed field on the old id. A field that
    # cannot be read is still deleted (the destroy would purge it anyway);
    # one that cannot be deleted is left for the purge.
    #
    # @return [Hash{String => Object}] the values that were present
    def take_completed_fields(old_sid, fields, db)
      fields.each_with_object({}) do |field, values|
        value = begin
          SessionSidecar.read(old_sid, field, dbclient: db)
        rescue StandardError
          nil
        end
        values[field] = value unless value.nil?
        SessionSidecar.delete(old_sid, field, dbclient: db)
      rescue StandardError => ex
        OT.lw "[session_rotation] completed field #{field} not deleted on the old id " \
              "(session_handle=#{handle(old_sid)}): #{ex.class}: #{ex.message}"
      end
    end

    # The old blob outlived the rotation: put the hand-off fields back so it
    # is in the state it was in. Best-effort; the caller refuses the flow
    # either way.
    def restore_completed_fields(old_sid, values, db)
      values.each do |field, value|
        SessionSidecar.write(old_sid, field, value, dbclient: db)
      rescue StandardError => ex
        OT.le "[session_rotation] completed field #{field} not restored on the surviving old id " \
              "(session_handle=#{handle(old_sid)}): #{ex.class}: #{ex.message}"
      end
    end

    # The marker is written before the blob is deleted, and the blob delete is
    # refused without it, so its presence is the one signal that the old id
    # is ended for in-flight writers as well as for the next request.
    def old_ended?(old_sid, db)
      SessionEnded.ended?(old_sid, dbclient: db)
    rescue StandardError => ex
      OT.le "[session_rotation] could not confirm the old id ended " \
            "(session_handle=#{handle(old_sid)}): #{ex.class}: #{ex.message}"
      false
    end

    # True when the old blob is still readable after one more direct delete.
    # A blob the store kept (its marker write failed) is deleted here under
    # the marker this module wrote; a delete that still leaves it is the
    # incomplete case.
    def old_blob_survived?(old_sid, db)
      store = store_operations
      key   = store.find_key(db, old_sid)
      return false if key.nil?

      store.destroy_blob(db, key)
      !store.find_key(db, old_sid).nil?
    rescue StandardError => ex
      OT.le "[session_rotation] could not confirm the old blob is gone " \
            "(session_handle=#{handle(old_sid)}): #{ex.class}: #{ex.message}"
      true
    end

    # The customer's active_sessions index still names the old id; the
    # record it pointed at is gone. ListForCustomer prunes dead entries on
    # read, so this is tidiness, never authority. Best-effort.
    def forget_old_index_entry(extid, old_sid)
      return if extid.to_s.empty? || old_sid.nil?

      Onetime::Customer.find_by_extid(extid)&.active_sessions&.remove(old_sid)
    rescue StandardError => ex
      OT.lw "[session_rotation] old id not removed from the customer's session index " \
            "(session_handle=#{handle(old_sid)}): #{ex.class}: #{ex.message}"
    end

    def handle(sid)
      SessionEnded.handle_for(sid)
    end

    # Loaded at first use, not at the top of this file: store.rb uses
    # absolute `require 'onetime/...'` lines, which need lib on the load path,
    # and the boot require chain (lib/onetime/session.rb pulls this file in)
    # cannot assume that; the Puma fork specs boot from a generated rackup
    # that only require_relatives lib/onetime.rb.
    def store_operations
      require_relative '../operations/sessions/store'
      Onetime::Operations::Sessions::Store
    end
  end
end

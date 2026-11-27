# lib/onetime/session/rotation.rb
#
# frozen_string_literal: true

require_relative '../session'
require_relative 'ended'
require_relative 'sidecar'

module Onetime
  # Renews the Rack session ID at a capability gain while preserving session
  # hash data. Full-mode login instead uses Rodauth's `clear_session`; simple
  # login clears the hash before calling this module. No renewal is needed for
  # capability loss or a transition any holder of the current ID can already make.
  #
  # Hash data carries over, including the Rodauth join key, surface, CSRF token,
  # and merged sidecar values. The active-session row is independent of the
  # Rack ID. Explicit-use sidecars, metadata, and the snapshot counter stay
  # behind; renewal starts a new snapshot epoch (ADR-046). Consume hand-off
  # state before renewal or record it fresh afterward. Name completed fields
  # via `completed:` to avoid false in-flight warnings during destroy.
  #
  # Mark the old ID before touching hand-off fields. Completion requires a new
  # ID, a confirmed marker, and no old blob. On an incomplete result, restore
  # completed field values where possible and do not grant the new capability.
  # A session without the Rack store interface returns nil. A Rack session
  # without an old ID returns an incomplete result.
  module Session::Rotation
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
      unless old_sid && Session::Ended.mark(old_sid, dbclient: db)
        OT.le '[session_rotation] session not rotated: ended marker could not be written ' \
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
      [:destroy, :to_hash, :update, :id].all? { |m| session.respond_to?(m) }
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
        value         = begin
          Session::Sidecar.read(old_sid, field, dbclient: db)
        rescue StandardError
          nil
        end
        values[field] = value unless value.nil?
        Session::Sidecar.delete(old_sid, field, dbclient: db)
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
        Session::Sidecar.write(old_sid, field, value, dbclient: db)
      rescue StandardError => ex
        OT.le "[session_rotation] completed field #{field} not restored on the surviving old id " \
              "(session_handle=#{handle(old_sid)}): #{ex.class}: #{ex.message}"
      end
    end

    # The marker is written before the blob is deleted, and the blob delete is
    # refused without it, so its presence is the one signal that the old id
    # is ended for in-flight writers as well as for the next request.
    def old_ended?(old_sid, db)
      Session::Ended.ended?(old_sid, dbclient: db)
    rescue StandardError => ex
      OT.le '[session_rotation] could not confirm the old id ended ' \
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
      OT.le '[session_rotation] could not confirm the old blob is gone ' \
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
      Session::Ended.handle_for(sid)
    end

    # Loaded at first use, not at the top of this file: store.rb uses
    # absolute `require 'onetime/...'` lines, which need lib on the load path,
    # and the boot require chain (lib/onetime/session/rack_store.rb pulls this file in)
    # cannot assume that; the Puma fork specs boot from a generated rackup
    # that only require_relatives lib/onetime.rb.
    def store_operations
      require_relative '../operations/sessions/store'
      Onetime::Operations::Sessions::Store
    end
  end
end

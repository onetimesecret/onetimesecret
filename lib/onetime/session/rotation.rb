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
  # data must SURVIVE: the second factor completing (RISK-2026-09-19-02) and
  # the colonel step-up (ColonelAPI::Logic::Colonel::ElevateSession). Simple-mode
  # password login (Core::Logic::Authentication::AuthenticateSession, which
  # Rodauth does not serve) also calls it, on a session it has cleared first:
  # nothing crosses, which matches what clear_session gives full mode, and
  # an incomplete result refuses the login.
  #
  # ## Which transitions renew the id
  #
  # The rule: the id is renewed when the session GAINS capability (anonymous
  # to signed in, partly to fully authenticated, a step-up window, a
  # credential change), so that a copy of the earlier id, planted in advance
  # or leaked, does not gain it too. It is not renewed when capability stays
  # the same or shrinks, or when whoever holds the id could already make the
  # transition at will: a new id would defend nothing, and it starts a new
  # snapshot epoch (ADR-046).
  #
  # Mechanisms: `clear_session` is Rodauth's login_session running this app's
  # clear_session (session.destroy), and nothing crosses; `rotate!` is this
  # module; `:renew` is `rack.session.options[:renew]`
  # (Onetime::Logic::Base#rotate_session!, or set by a Rodauth hook), applied
  # by Rack at commit, and the session data crosses. Each line names the
  # spec that shows the new id, or says there is none.
  #
  # - Password sign-in, full mode: renewed, clear_session.
  #   spec/integration/full/customer_session_continuation_baseline_spec.rb:18
  # - Password sign-in, simple mode: renewed, session cleared then rotate!.
  #   spec/integration/simple/login_session_rotation_spec.rb:117
  # - OIDC callback sign-in (first sign-in and returning identity): renewed,
  #   clear_session (rodauth-omniauth login("omniauth")).
  #   apps/web/auth/spec/integration/full/sso_callback_session_rotation_spec.rb:124, :134
  # - Platform SAML callback sign-in: renewed, clear_session.
  #   apps/web/auth/spec/integration/full_saml_platform/platform_saml_sso_spec.rb:705
  # - Verify-account autologin: renewed, clear_session (autologin_session).
  #   apps/web/auth/spec/integration/full/verify_account_autologin_session_rotation_spec.rb:123
  # - Magic-link and passkey sign-in: renewed, clear_session (Rodauth
  #   `login`, the same route family). No rotation spec.
  # - SSO link-confirm sign-in and link-SSO password sign-in: renewed,
  #   clear_session (`rodauth.login` in apps/web/auth/routes/sso_link_confirm.rb
  #   and apps/web/auth/routes/link_sso.rb). No rotation spec.
  # - SSO Connect callback (binds an identity to the signed-in account):
  #   renewed, clear_session (the callback ends in rodauth-omniauth
  #   login("omniauth"); hooks/omniauth.rb, "Post-Connect Return Path").
  #   No rotation spec.
  # - Second factor completed: renewed, rotate! (hooks/two_factor.rb).
  #   apps/web/auth/spec/integration/full_mfa/mfa_session_rotation_spec.rb:81
  # - Invite signup autologin: renewed, :renew.
  #   spec/integration/full/active_sessions_spec.rb:624
  # - Password change, full mode: renewed, :renew (after_change_password).
  #   spec/integration/full/hooks/account_lifecycle_spec.rb:487
  # - Password change, simple mode: renewed, :renew
  #   (AccountAPI::Logic::Account::UpdatePassword). No rotation spec.
  # - Colonel step-up: renewed, rotate!; no window when it is incomplete.
  #   spec/integration/full/colonel_elevation_session_rotation_spec.rb:69,
  #   spec/integration/simple/colonel_elevation_session_rotation_spec.rb:67
  # - Impersonation start and stop: none, by rule (any holder of the colonel
  #   id can start one without a step-up; the overlay is read-only; stop
  #   returns the colonel's own capability). See
  #   Auth::Operations::Customers::Impersonate#call.
  # - Organization switch (RequestHelpers#switch_organization): none, by
  #   rule; it changes the active organization, not the identity.
  # - Dropping elevation: none, by rule; capability shrinks.
  # - Sign-out, and simple-mode password reset: the id is ended (cleared,
  #   then :renew, or clear_session in full mode) and nothing signed in
  #   crosses. Not a rotation in this module's sense, and none is required
  #   by the rule.
  #
  # Open: these raise what the session can do and keep its id. Both are
  # recorded in RISK-2026-09-19-02 (docs/security/active-risk-register.md).
  #
  # - Re-authentication proof (POST /auth/reauth): not renewed.
  #   Auth::Operations::Reauthenticate#record writes the single-use
  #   Onetime::RecentReauth proof under the current id.
  # - TOTP and passkey setup: not renewed. Rodauth's
  #   two_factor_update_session adds the factor to the session.
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
  # An incomplete result means the caller must not complete the transition
  # on the session. A sign-in raises {Onetime::SessionRotation::Incomplete}
  # after clearing the session hash (the MFA hook and simple-mode login do
  # this; the request then fails and the cleared hash is what the commit
  # writes). The colonel step-up writes no window and answers an error, and
  # leaves the rest of the session as it was. A session that is not a Rack
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

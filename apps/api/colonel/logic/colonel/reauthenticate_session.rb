# apps/api/colonel/logic/colonel/reauthenticate_session.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/security/colonel_rate_limiter'
require 'onetime/session/rotation'
require 'onetime/operations/sessions/track_metadata'

module ColonelAPI
  module Logic
    module Colonel
      # POST /api/colonel/reauthenticate — get a lapsed admin session window
      # back by re-entering the account password.
      #
      # Onetime::Application::AuthStrategies::AdminSessionLifetime bounds every
      # /api/colonel request with an idle and an absolute timeout (#4331).
      # When one trips, every admin API call answers 401
      # `admin_session_expired`. This endpoint is the one request those bounds
      # do not refuse (AdminSessionLifetime::REAUTH_EXEMPT, where the reasons
      # it does not weaken them are listed), so the console can recover the
      # window in place instead of signing the operator out.
      #
      # What a verified password does, in order:
      #
      #   1. Renews the session id (Onetime::SessionRotation.rotate!), with
      #      the refusal semantics of ElevateSession#start_elevated_session!:
      #      the capability being restored is the admin surface, so a copy of
      #      the pre-proof id must not get it back too.
      #   2. Re-stamps `authenticated_at` to now, which restarts the absolute
      #      bound. Plain `now`, not UpdatePassword's `[now, watermark + 1].max`:
      #      a password change that lands in this same second is meant to
      #      retire this session, and stamping past it would undo that.
      #   3. Drops any step-up window. Re-authentication has fresh-sign-in
      #      semantics and grants no elevation; tier-1 verbs still need
      #      POST /api/colonel/elevation.
      #   4. Writes the new id's SessionMetadata through TrackMetadata, which
      #      restarts the idle bound. The commit skips that write on this
      #      request when a bound had tripped (see REAUTH_EXEMPT), so the
      #      handler does it after the proof.
      #   5. Re-reads the credential watermark, so a password change that
      #      landed during the request still retires the session
      #      (#refuse_if_credentials_changed!).
      #
      # Re-stamping authenticated_at is what a sign-in does, so it also
      # restarts the site-wide absolute lifetime Onetime::Session measures
      # from the blob's stamp (simple mode). In full mode the active-session
      # row keeps its created_at, and that bound still counts from the
      # original sign-in.
      #
      # Same rotation, same tidy-up as ElevateSession: rotate! itself destroys
      # the old id's SessionMetadata record and its active_sessions entry, and
      # the active-session row (keyed by active_session_id_hmac, which the
      # session hash carries across) is untouched. UpdatePassword tidies those
      # by hand because its :renew rotation happens later, at commit.
      #
      # AUDIT — shares ElevateSession's documented exception to CONTRACT 4,
      # as DropElevation does: there is no Operations class because the
      # mutation is a session field. Success -> .record (bounded by the
      # limiter). Failure -> .record_security (drivable on demand by whoever
      # holds the cookie), including a verified password whose session id
      # could not be renewed (`reason: 'session_not_rotated'`).
      #
      # The submitted password is NEVER sanitized, NEVER logged, NEVER echoed
      # and has no attr_reader.
      #
      # Accounts with no password (SSO-only) cannot use this endpoint; they
      # sign out and in again, as before.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ReauthenticateSession < ColonelAPI::Logic::Base
        include Onetime::Security::ColonelRateLimiter

        AUDIT_VERB = 'colonel.reauthenticate'

        # The audit `reason` and the console message for a verified password
        # whose session id could not be renewed.
        ROTATION_FAILED_REASON  = 'session_not_rotated'
        ROTATION_FAILED_MESSAGE = 'Re-authentication could not be completed. Please try again.'

        # The audit `reason` when the account password changed while this
        # request ran (#refuse_if_credentials_changed!).
        CREDENTIALS_CHANGED_REASON = 'credentials_changed'

        def process_params
          # Deliberately raw and deliberately not exposed.
          @password = params['password'].to_s
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          # Throttle BEFORE verifying, on the step-up bucket: both endpoints
          # take the same password through the same internal check, which does
          # not increment Rodauth's lockout counter, so they share one guessing
          # budget. A lockout is recorded under the step-up throttle verb.
          enforce_colonel_elevation_limit!(cust.extid)
        end

        def process
          unless verify_elevation_password(@password)
            record_failure_audit
            raise Onetime::ReauthenticationFailed
          end

          signed_in_at = sess['authenticated_at'].to_i
          @rotation    = renew_session_id!

          @authenticated_at        = Familia.now.to_i
          sess['authenticated_at'] = @authenticated_at
          drop_elevation!
          record_activity
          refuse_if_credentials_changed!(signed_in_at)

          record_success_audit

          success_data
        end

        def success_data
          {
            record: {
              reauthenticated: true,
              authenticated_at: @authenticated_at,
            },
            details: {
              session_rotated: @rotation&.complete == true,
            },
          }
        end

        private

        # See ElevateSession#start_elevated_session! for the rationale; the
        # semantics are the same. A nil result is a session with no
        # server-side id (a bare Hash, as in the unit specs) and the
        # re-authentication continues; sessionauth, the only strategy on this
        # route, always hands over a Rack session.
        #
        # @return [Onetime::SessionRotation::Result, nil]
        # @raise [Onetime::ReauthenticationFailed] when the old id could not be ended
        def renew_session_id!
          previous_handle = session_log_handle

          rotation = begin
            Onetime::SessionRotation.rotate!(sess)
          rescue StandardError => ex
            refuse_unrotated_session!(previous_handle, reason: :error, error: "#{ex.class}: #{ex.message}")
          end

          if rotation.nil?
            OT.lw '[ReauthenticateSession] session id not rotated: no server-side session id',
              user_id: cust.objid,
              session_class: sess.class.name
            return nil
          end

          refuse_unrotated_session!(previous_handle, reason: rotation.reason) unless rotation.complete

          OT.li '[ReauthenticateSession] session id rotated',
            user_id: cust.objid,
            previous_session_handle: Onetime::SessionEnded.handle_for(rotation.old_sid),
            session_handle: Onetime::SessionEnded.handle_for(rotation.new_sid)

          rotation
        end

        # Nothing is re-stamped on a session whose old id could not be ended:
        # the window stays lapsed and the operator signs in again. See
        # ElevateSession#refuse_unrotated_session! for which id survives.
        # Handles only, never session ids (#4461).
        def refuse_unrotated_session!(previous_handle, reason:, error: nil)
          OT.le '[ReauthenticateSession] re-authentication refused: the previous session id could not be ended',
            user_id: cust.objid,
            previous_session_handle: previous_handle,
            session_handle: session_log_handle,
            reason: reason,
            error: error

          record_failure_audit(reason: ROTATION_FAILED_REASON)
          raise Onetime::ReauthenticationFailed, ROTATION_FAILED_MESSAGE
        end

        # The auth strategy refused this session if it predated the credential
        # watermark (customer.last_password_update), but a password change can
        # land after that check and before the re-stamp above, and the re-stamp
        # would then carry this session past the new watermark. So the
        # watermark is read again, fresh, after the stamp (and after the new id
        # is indexed, which is what a concurrent revoke walks). A change since
        # this session signed in puts the old stamp back, which the next
        # request refuses as stale_credentials, and answers the failure.
        def refuse_if_credentials_changed!(signed_in_at)
          watermark = Onetime::Customer.load(cust.objid)&.last_password_update.to_i
          return unless watermark.positive? && signed_in_at <= watermark

          sess['authenticated_at'] = signed_in_at
          OT.lw '[ReauthenticateSession] re-authentication refused: credentials changed during the request',
            user_id: cust.objid
          record_failure_audit(reason: CREDENTIALS_CHANGED_REASON)
          raise Onetime::ReauthenticationFailed
        end

        # Step 4 of the class header. TrackMetadata is the single writer of
        # the record and never raises; with env: nil it treats this call as
        # activity. Skipped when the session has no server-side id.
        def record_activity
          sid = @rotation&.new_sid
          return if sid.to_s.empty?

          Onetime::Operations::Sessions::TrackMetadata.new(
            session_id: sid,
            session_data: sess.to_hash,
          ).call
        end

        def record_success_audit
          Onetime::ColonelAuditEvent.record(
            actor: cust.extid,
            verb: AUDIT_VERB,
            target: cust.extid,
            result: :success,
          )
        rescue StandardError => ex
          OT.le('[ReauthenticateSession] audit record failed', exception: ex)
        end

        def record_failure_audit(reason: nil)
          Onetime::ColonelAuditEvent.record_security(
            actor: cust.extid,
            verb: AUDIT_VERB,
            target: cust.extid,
            result: :failure,
            detail: reason ? { reason: reason } : nil,
          )
        rescue StandardError => ex
          OT.le('[ReauthenticateSession] security audit record failed', exception: ex)
        end
      end
    end
  end
end

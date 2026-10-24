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
      # ## Accounts with a second factor (full mode)
      #
      # Sign-in and the app's own POST /auth/reauth ask for the second factor
      # when the account has one (Auth::Operations::MfaStateChecker); this
      # endpoint takes a password only. So in full mode an account with any
      # second factor enrolled (TOTP, recovery codes or a WebAuthn key,
      # whether or not that factor's feature is on) is refused with
      # Onetime::ReauthenticationUnavailable and signs in again. The same
      # refusal answers when the check cannot complete: no account row
      # carries the customer's extid, or the auth database read raises. The
      # check runs after the rate limiter and BEFORE the password, so an MFA
      # account gets the same answer whatever password was sent (no
      # password oracle), and nothing is rotated or re-stamped. Simple mode
      # has no second factor and never runs the check.
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
      # A verified password whose session id could not be renewed is refused
      # and nothing is re-stamped (#refuse_unrotated_session!). An incomplete
      # rotation can still have moved the session to a new id, which the
      # commit saves without a SessionMetadata record (it skips TrackMetadata
      # on this request, see REAUTH_EXEMPT). With no record the next request
      # would skip the idle check, so the refusal writes the new id's record
      # with the OLD id's last_activity_at (#carry_idle_clock!) and the idle
      # bound stays as lapsed as it was.
      #
      # AUDIT — shares ElevateSession's documented exception to CONTRACT 4,
      # as DropElevation does: there is no Operations class because the
      # mutation is a session field. Success -> .record (bounded by the
      # limiter). Failure -> .record_security (drivable on demand by whoever
      # holds the cookie), including a verified password whose session id
      # could not be renewed (`reason: 'session_not_rotated'`) and a full-mode
      # account refused for its second factor (`reason: 'mfa_required'`).
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

        # The audit `reason` for a full-mode account refused because a
        # second factor is enrolled, or its state could not be read
        # (#refuse_if_second_factor!).
        MFA_REQUIRED_REASON = 'mfa_required'

        # SessionMetadata fields #carry_idle_clock! copies from the old id's
        # record to the new id's.
        CARRIED_METADATA_FIELDS = [
          :user_id,
          :org_id,
          :created_at,
          :last_activity_at,
          :ip_address,
          :user_agent,
          :auth_method,
          :mfa_used,
          :active_session_id_hmac,
          :geo_country,
        ].freeze

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
          refuse_if_second_factor!

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
          previous_handle  = session_log_handle
          previous_sid     = plain_session_id
          # Read before rotate!, which destroys the old id's record.
          @previous_record = previous_sid && load_session_record(previous_sid)

          rotation = begin
            Onetime::SessionRotation.rotate!(sess)
          rescue StandardError => ex
            refuse_unrotated_session!(
              previous_handle,
              previous_sid,
              reason: :error,
              error: "#{ex.class}: #{ex.message}",
            )
          end

          if rotation.nil?
            OT.lw '[ReauthenticateSession] session id not rotated: no server-side session id',
              user_id: cust.objid,
              session_class: sess.class.name
            return nil
          end

          refuse_unrotated_session!(previous_handle, previous_sid, reason: rotation.reason) unless rotation.complete

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
        def refuse_unrotated_session!(previous_handle, previous_sid, reason:, error: nil)
          OT.le '[ReauthenticateSession] re-authentication refused: the previous session id could not be ended',
            user_id: cust.objid,
            previous_session_handle: previous_handle,
            session_handle: session_log_handle,
            reason: reason,
            error: error

          carry_idle_clock!(previous_sid)
          record_failure_audit(reason: ROTATION_FAILED_REASON)
          raise Onetime::ReauthenticationFailed, ROTATION_FAILED_MESSAGE
        end

        # An incomplete rotation that still renewed the id (:marker_not_confirmed,
        # :blob_survived, or a raise after the re-key) leaves the session under
        # a new id with no SessionMetadata record, and the commit does not write
        # one (EXPIRED_ENV_KEY). AdminSessionLifetime skips the idle check for
        # a session without a record, so the next admin request would pass it.
        # Writing the new id's record from the old one, last_activity_at
        # included, keeps the idle bound where it was; indexing it keeps the
        # id reachable by a revoke of all the customer's sessions.
        #
        # Nothing to carry when the id did not change, or when the old id had
        # no record: its idle check was already skipped before this request,
        # so the new id is no less bounded. Best-effort, like TrackMetadata.
        def carry_idle_clock!(previous_sid)
          current_sid = plain_session_id
          return if current_sid.nil? || current_sid == previous_sid
          return if @previous_record.nil?

          last_activity_at = @previous_record.last_activity_at.to_i
          return unless last_activity_at.positive?

          fields = CARRIED_METADATA_FIELDS.to_h { |name| [name, @previous_record.public_send(name)] }
          fields = fields.compact.merge(session_id: current_sid, last_activity_at: last_activity_at)
          Onetime::SessionMetadata.new(**fields).save
          cust.active_sessions.add(current_sid, last_activity_at)

          OT.lw '[ReauthenticateSession] idle clock carried to the renewed session id',
            user_id: cust.objid,
            session_handle: Onetime::SessionEnded.handle_for(current_sid)
        rescue StandardError => ex
          OT.le '[ReauthenticateSession] idle clock not carried to the renewed session id',
            user_id: cust.objid,
            error: "#{ex.class}: #{ex.message}"
        end

        # Full mode only (see "Accounts with a second factor" above). MUST test
        # full_enabled? before naming Auth::*: registry.rb drops apps/web/auth
        # in simple mode, so the constants do not exist there.
        def refuse_if_second_factor!
          return unless Onetime.auth_config.full_enabled?
          return if second_factor_absent?

          OT.lw '[ReauthenticateSession] re-authentication refused: second factor enrolled or unreadable',
            user_id: cust.objid
          record_failure_audit(reason: MFA_REQUIRED_REASON)
          raise Onetime::ReauthenticationUnavailable
        end

        # True only when the check completed and found no second factor.
        # FAIL CLOSED: no account row, or any error, counts as enrolled.
        def second_factor_absent?
          db         = Auth::Database.connection
          account_id = db && db[:accounts].where(external_id: cust.extid).get(:id)
          return false if account_id.nil?

          !Auth::Operations::MfaStateChecker.new(db).check(account_id).mfa_enabled?
        rescue StandardError => ex
          OT.le '[ReauthenticateSession] second-factor check failed; refusing',
            user_id: cust.objid,
            error: "#{ex.class}: #{ex.message}"
          false
        end

        # The plain session id, or nil for a session with none (a bare Hash).
        def plain_session_id
          sid = safe_session_id
          sid = sid.public_id if sid.respond_to?(:public_id)
          sid = sid.to_s
          sid.empty? ? nil : sid
        rescue StandardError
          nil
        end

        def load_session_record(sid)
          Onetime::SessionMetadata.load(sid)
        rescue StandardError => ex
          OT.le '[ReauthenticateSession] session record read failed',
            user_id: cust.objid,
            error: "#{ex.class}: #{ex.message}"
          nil
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
          # A customer record that vanished mid-request fails closed: nothing
          # proves the re-stamp postdates its credentials.
          fresh     = Onetime::Customer.load(cust.objid)
          watermark = fresh ? fresh.last_password_update.to_i : nil
          return if watermark && !(watermark.positive? && signed_in_at <= watermark)

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

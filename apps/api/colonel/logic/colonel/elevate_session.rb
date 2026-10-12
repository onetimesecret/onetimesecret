# apps/api/colonel/logic/colonel/elevate_session.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/security/colonel_rate_limiter'
require 'onetime/session/rotation'

module ColonelAPI
  module Logic
    module Colonel
      # POST /api/colonel/elevation — mint a step-up (sudo) window (#4327).
      #
      # Two factors, both defined in {Elevation}:
      #
      #   password    — dual-mode re-verification, the only factor available by
      #                 default and the only one a password-holding account may
      #                 ever use.
      #   recent_auth — elevate with no further credential inside a post-sign-in
      #                 grace. Available ONLY to accounts that cannot satisfy the
      #                 password factor, and ONLY when an operator configured a
      #                 non-zero grace (the shipped default is 0). Handing it to
      #                 password holders would make step-up a no-op for the first
      #                 N seconds after every colonel sign-in, which is verbatim
      #                 the condition #4327 exists to remove.
      #
      # AUDIT — a documented FOURTH exception to CONTRACT 4 ("the Operations
      # class owns the ColonelAuditEvent; adapters do not audit"). There is no
      # Operations class here because the mutation is a session field, not a
      # model. Do not add a fifth.
      #
      #   success -> .record          (authenticated operator activity, bounded
      #                                to `max_attempts` per lockout window by
      #                                the limiter below). The `factor` detail is
      #                                REQUIRED: it is what makes a recent_auth
      #                                elevation visible in the trail as the
      #                                weaker path.
      #   failure -> .record_security (drivable on demand by whoever holds the
      #                                cookie; the operator trail is count-capped
      #                                with no TTL). A factor that verified but
      #                                whose session id could not be renewed
      #                                (below) is a failure too, with
      #                                `reason: 'session_not_rotated'`: no
      #                                window was granted.
      #   refusal of a tier-1 verb for want of elevation -> nothing at all, see
      #                                DestructiveAction#require_elevation!.
      #
      # The submitted password is NEVER sanitized, NEVER logged, NEVER echoed and
      # has no attr_reader. ColonelAuditEvent's SENSITIVE_KEY_PATTERN would blank
      # it; do not rely on that.
      #
      # SESSION ID (#4466). The window gives this session id tier-1 capability,
      # so it is written under a NEW id: once the factor verifies,
      # {Onetime::SessionRotation.rotate!} ends the old id the way a logout
      # does and carries the session data (identity, active-session join key,
      # surface marker, CSRF token) to a new one, then the window is written.
      # A copy of the pre-step-up id is then signed out rather than elevated
      # (spec/integration/full/colonel_elevation_session_rotation_spec.rb).
      # The response sets the new cookie; the console adopts the new snapshot
      # epoch through an auth-mutation refresh
      # (src/apps/admin/composables/useColonelElevation.ts).
      #
      # If the old id cannot be ended, no window is granted and the request
      # answers {Onetime::ElevationFailed}. See #refuse_unrotated_session! for
      # what that leaves the operator with.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ElevateSession < ColonelAPI::Logic::Base
        include Onetime::Security::ColonelRateLimiter

        AUDIT_VERB = 'colonel.elevate'

        # The audit `reason` and the console message for a verified factor
        # whose session id could not be renewed.
        ROTATION_FAILED_REASON  = 'session_not_rotated'
        ROTATION_FAILED_MESSAGE = 'Step-up could not be completed. Please try again.'

        attr_reader :factor

        def process_params
          @factor   = sanitize_plain_text(params['factor']).to_s.strip
          @factor   = 'password' if factor.empty?
          # Deliberately raw and deliberately not exposed.
          @password = params['password'].to_s
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          raise_form_error("Unknown step-up factor '#{factor}'", field: :factor) unless Elevation::FACTORS.include?(factor)
          raise_form_error('Step-up authentication is disabled', field: :factor) unless elevation_enabled?

          # Throttle BEFORE verifying. Auth::Config.valid_login_and_password? is
          # an internal request: it is not a login and it does not increment
          # Rodauth's lockout counter, so this is the only backstop against
          # password guessing here.
          enforce_colonel_elevation_limit!(cust.extid)
        end

        def process
          verified = case factor
                     when 'password'    then verify_elevation_password(@password)
                     when 'recent_auth' then within_reauth_grace?
                     end

          unless verified
            record_failure_audit
            raise Onetime::ElevationFailed.new(failure_message, factor: factor)
          end

          start_elevated_session!
          grant_elevation!
          record_success_audit

          success_data
        end

        def success_data
          {
            record: {
              elevated: true,
              expires_at: elevated_until,
              seconds_remaining: elevation_seconds_remaining,
            },
            details: {
              factor: factor,
              window: elevation_window,
            },
          }
        end

        private

        # Move the session to a new id before the window is written (#4466,
        # see the class header). Nothing is removed from the session: the
        # operator stays signed in.
        #
        # A nil result is a session that is not a Rack session-store session
        # (a bare Hash, as in the unit specs): it has no server-side id that
        # could have been copied, so the step-up continues, as the MFA hook and
        # simple-mode login do for the same case. sessionauth, the only
        # strategy on this route, always hands over a Rack session.
        #
        # @raise [Onetime::ElevationFailed] when the old id could not be ended
        def start_elevated_session!
          previous_handle = session_log_handle

          rotation = begin
            Onetime::SessionRotation.rotate!(sess)
          rescue StandardError => ex
            refuse_unrotated_session!(previous_handle, reason: :error, error: "#{ex.class}: #{ex.message}")
          end

          if rotation.nil?
            OT.lw '[ElevateSession] session id not rotated: no server-side session id',
              user_id: cust.objid,
              session_class: sess.class.name
            return
          end

          refuse_unrotated_session!(previous_handle, reason: rotation.reason) unless rotation.complete

          OT.li '[ElevateSession] session id rotated',
            user_id: cust.objid,
            previous_session_handle: Onetime::SessionEnded.handle_for(rotation.old_sid),
            session_handle: Onetime::SessionEnded.handle_for(rotation.new_sid)
        end

        # No window on a session whose old id could not be ended. rotate!
        # writes the session data back whatever happened, so the operator
        # stays signed in, unelevated: under the old id when nothing was
        # touched (:marker_not_written), under the new one when the old id
        # survived the re-key (:blob_survived, :marker_not_confirmed). When
        # the old id was marked ended but not re-keyed (:not_rekeyed, or a
        # raise after the marker was written), the request's commit refuses
        # that id and the operator signs in again. Handles only, never session ids (#4461).
        def refuse_unrotated_session!(previous_handle, reason:, error: nil)
          OT.le '[ElevateSession] step-up refused: the previous session id could not be ended',
            user_id: cust.objid,
            previous_session_handle: previous_handle,
            session_handle: session_log_handle,
            reason: reason,
            error: error

          record_failure_audit(reason: ROTATION_FAILED_REASON)
          raise Onetime::ElevationFailed.new(ROTATION_FAILED_MESSAGE, factor: factor)
        end

        # Distinguish the three ways recent_auth can fail so the console can help
        # rather than loop. None of these is an oracle: every fact is already in
        # GET /api/colonel/elevation for the caller's OWN account.
        def failure_message
          return 'Password verification failed.' if factor == 'password'

          if elevation_password_available?
            # In FULL auth mode the password factor cannot be probed from the
            # logic layer, so EVERY account is treated as password-holding
            # (fail-closed) — including SSO-only ones that have no password.
            # Telling such an operator to "re-enter your password" is
            # misinformation, so name what actually applies in full mode:
            # recent_auth is categorically unavailable there, password holders
            # elevate with their password, and an SSO-only fleet needs elevation
            # disabled.
            if Onetime.auth_config.full_enabled?
              'Password-less (recent_auth) step-up is not available in full ' \
                'authentication mode. Elevate with your account password, or for ' \
                'an SSO-only fleet ask an administrator to set ' \
                'COLONEL_ELEVATION_ENABLED=false.'
            else
              'This account has a password; re-enter it to elevate.'
            end
          elsif elevation_reauth_grace.zero?
            'Password-less step-up is not enabled on this install. ' \
              'Ask an administrator to set COLONEL_ELEVATION_REAUTH_GRACE.'
          else
            'Sign-in is not recent enough to elevate. Sign out and sign in again.'
          end
        end

        def record_success_audit
          Onetime::ColonelAuditEvent.record(
            actor: cust.extid,
            verb: AUDIT_VERB,
            target: cust.extid,
            result: :success,
            detail: { factor: factor, window: elevation_window },
          )
        rescue StandardError => ex
          OT.le('[ElevateSession] audit record failed', exception: ex)
        end

        def record_failure_audit(reason: nil)
          detail          = { factor: factor }
          detail[:reason] = reason if reason

          Onetime::ColonelAuditEvent.record_security(
            actor: cust.extid,
            verb: AUDIT_VERB,
            target: cust.extid,
            result: :failure,
            detail: detail,
          )
        rescue StandardError => ex
          OT.le('[ElevateSession] security audit record failed', exception: ex)
        end
      end
    end
  end
end

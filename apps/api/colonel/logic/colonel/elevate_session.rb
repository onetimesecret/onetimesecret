# apps/api/colonel/logic/colonel/elevate_session.rb
#
# frozen_string_literal: true

require_relative '../base'
require 'onetime/security/colonel_rate_limiter'

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
      #                                with no TTL).
      #   refusal of a tier-1 verb for want of elevation -> nothing at all, see
      #                                DestructiveAction#require_elevation!.
      #
      # The submitted password is NEVER sanitized, NEVER logged, NEVER echoed and
      # has no attr_reader. ColonelAuditEvent's SENSITIVE_KEY_PATTERN would blank
      # it; do not rely on that.
      #
      # Security invariant (epic #20): BOTH the router (role=colonel) AND this
      # logic (verify_one_of_roles!(colonel: true)) enforce the colonel role.
      class ElevateSession < ColonelAPI::Logic::Base
        include Onetime::Security::ColonelRateLimiter

        AUDIT_VERB = 'colonel.elevate'

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

        # Distinguish the three ways recent_auth can fail so the console can help
        # rather than loop. None of these is an oracle: every fact is already in
        # GET /api/colonel/elevation for the caller's OWN account.
        def failure_message
          return 'Password verification failed.' if factor == 'password'

          if elevation_password_available?
            'This account has a password; re-enter it to elevate.'
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

        def record_failure_audit
          Onetime::ColonelAuditEvent.record_security(
            actor: cust.extid,
            verb: AUDIT_VERB,
            target: cust.extid,
            result: :failure,
            detail: { factor: factor },
          )
        rescue StandardError => ex
          OT.le('[ElevateSession] security audit record failed', exception: ex)
        end
      end
    end
  end
end

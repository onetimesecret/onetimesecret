# lib/onetime/session/remember_me.rb
#
# frozen_string_literal: true

module Onetime
  # "Remember me": a session signed in with the box ticked lasts a fixed
  # {DURATION} from sign-in instead of the default rolling 24 hours.
  #
  # ## The mechanism
  #
  # The choice extends THIS session. Nothing else is issued: no second
  # cookie, no token table. The login stamps the deadline in two places:
  #
  # - the Rack session, as `remember_until` (integer epoch), which
  #   {Onetime::Session} reads to give the blob and the cookie that fixed
  #   lifetime. Both auth modes.
  # - the active-session row, as `remember_until` (timestamp, written in the
  #   database's clock), which {Onetime::ActiveSessionGate} and Rodauth's
  #   sweep read to exempt the row from the inactivity deadline until then.
  #   Full mode only (apps/web/auth/config/features/remember_me.rb).
  #
  # Revocation is unchanged because there is still exactly one Rack session
  # and one active-session row: every path that ends a session today ends a
  # remembered one the same way.
  #
  # Rodauth's own remember feature is deliberately not used. Its key is one
  # per account, shared by every device that ticked the box, so revoking one
  # device's session from the sessions page could not end that device's
  # remembered login without ending the others', and every revocation path
  # would have to learn to remove it.
  #
  # ## What is not extended
  #
  # The deadline is fixed at sign-in, as Rodauth's remember_deadline_interval
  # is, and never moves with activity. The 30-day lifetime deadline still
  # applies, on the row and (from `authenticated_at`) on the blob, and so
  # does the colonel's absolute session bound (AdminSessionLifetime), which
  # is shorter.
  #
  # ## Where the deadline is enforced
  #
  # On the read, in both modes. {Onetime::Session#find_session} ends a
  # session whose stamp has passed (the blob TTL only sizes the key), and
  # {Onetime::ActiveSessionGate} refuses a row whose `remember_until` has
  # passed. Neither depends on the switch: a deadline that has passed has
  # passed. The switch governs only whether a sign-in is stamped and whether
  # a stamp still exempts the row from the inactivity deadline and sizes the
  # blob and cookie to it.
  #
  # ## Two clocks
  #
  # The blob's stamp is a Ruby epoch and the row's is the database's
  # CURRENT_TIMESTAMP, written in the same login. Skew between them is
  # harmless: in full mode either one lapsing ends the session (the row via
  # the gate, the blob via the read), so the earlier clock wins and the
  # failure is closed.
  module RememberMe
    extend self

    # Rack session key. String, the app-session convention.
    SESSION_KEY = 'remember_until'

    # 14 days: Rodauth's remember_deadline_interval default.
    DURATION = 14 * 86_400

    # The login form's parameter (src/shared/composables/useAuth.ts).
    PARAM = 'remember-me'

    # The values that mean "ticked": a JSON boolean from the SPA, and the
    # strings a form post or a query string can carry. Anything else,
    # including absence, means no.
    TRUTHY = [true, 'true', '1', 'on'].freeze

    # @param value [Object] the raw request parameter
    # @return [Boolean]
    def requested?(value)
      TRUTHY.include?(value)
    end

    # Whether this install honours the checkbox (AUTH_REMEMBER_ME_ENABLED),
    # in either auth mode. Read on every session write, so it never raises:
    # an unreadable config means not remembered, i.e. the default session.
    #
    # Turning the switch off also ends the remembered lifetime of sessions
    # already stamped: {remaining} stops honouring the stamp (the next write
    # gives the blob the default TTL and the cookie the default lifetime),
    # and the gate stops exempting their rows from the inactivity deadline.
    def enabled?
      Onetime.auth_config.remember_me_sessions_enabled?
    rescue StandardError
      false
    end

    # Stamp the fixed deadline into the Rack session.
    #
    # @return [Integer] the deadline, epoch seconds
    def stamp(session, now: Time.now)
      session[SESSION_KEY] = now.to_i + DURATION
    end

    # Seconds left until the session's remember deadline, or nil when the
    # session is not remembered: no stamp, a value that is not an integer
    # epoch, or the switch is off. Capped at {DURATION}, so no stored value
    # can give a session a longer life than a fresh sign-in would.
    #
    # A stamp in the past is nil too, but never reaches this in practice:
    # {Onetime::Session#find_session} ends a session whose integer stamp has
    # passed before anything reads it (see #absolute_remaining there), and a
    # write that straddled the deadline gets a blob TTL of one second, not
    # the rolling default. So a nil here means "not remembered", and the
    # caller's fallback to the default lifetime is the right one.
    #
    # @param session [Hash, #[], nil] the Rack session or its data hash
    # @return [Integer, nil]
    def remaining(session, now: Time.now)
      return nil unless session.respond_to?(:[])

      deadline = session[SESSION_KEY]
      return nil unless deadline.is_a?(Integer) && enabled?

      left = deadline - now.to_i
      left.positive? ? [left, DURATION].min : nil
    end
  end
end

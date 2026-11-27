# lib/onetime/session/remember_me.rb
#
# frozen_string_literal: true

require_relative '../session'

module Onetime
  # Extends one session for a fixed {DURATION} from sign-in, with no extra
  # cookie or account-wide token, so per-device revocation is unchanged.
  #
  # The Rack blob stores an epoch deadline for reads and cookie/blob lifetime.
  # In full mode the active-session row also stores a database-clock deadline
  # that replaces inactivity while enabled. Either expired stamp ends the
  # session even after the feature is disabled. When disabled, writes cap the
  # rolling lifetime at any existing stamp. Activity never moves the deadline,
  # and absolute session and admin bounds still apply.
  module Session::RememberMe
    extend self

    # Rack session key. String, the app-session convention.
    SESSION_KEY = 'remember_until'

    # 30 days, the lifetime the sign-in form states
    # (web.COMMON.remember_me_description). It equals the default absolute
    # lifetime (Onetime::ActiveSessionGate::DEFAULT_LIFETIME_DEADLINE), so by
    # default the two deadlines fall together; a shorter
    # `site.session.absolute_timeout` ends a remembered session first.
    DURATION = 30 * 86_400

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
    # already stamped: {remaining} stops honouring the stamp, so the next
    # write gives the blob and the cookie the rolling default, bounded by
    # the stamp when that is nearer (a passed stamp still ends the session
    # on the read, whatever the switch says), and the gate stops exempting
    # their rows from the inactivity deadline.
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
    # {Onetime::Session::RackStore#find_session} ends a session whose integer stamp has
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

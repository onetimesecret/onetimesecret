# lib/onetime/session/auth_status.rb
#
# frozen_string_literal: true

require_relative 'customer_session_evaluator'

module Onetime
  # Projects a CustomerSessionEvaluator verdict into the public bootstrap
  # `auth_status`. Rejections appear as `anonymous` without a reason;
  # `unavailable` is not a sign-out, and `checking` is client-only.
  # AuthenticationSerializer derives the legacy `authenticated` and
  # `awaiting_mfa` flags from this status.
  module SessionAuthStatus
    AUTHENTICATED = 'authenticated'
    ANONYMOUS     = 'anonymous'
    MFA_PENDING   = 'mfa_pending'
    UNAVAILABLE   = 'unavailable'

    VALUES = [AUTHENTICATED, ANONYMOUS, MFA_PENDING, UNAVAILABLE].freeze

    BY_VERDICT_STATUS = {
      authenticated: AUTHENTICATED,
      mfa_pending: MFA_PENDING,
      anonymous: ANONYMOUS,
      rejected: ANONYMOUS,
      unavailable: UNAVAILABLE,
    }.freeze

    class << self
      # @param verdict [Onetime::CustomerSessionEvaluator::Verdict]
      # @return [String] one of VALUES
      def for_verdict(verdict)
        BY_VERDICT_STATUS.fetch(verdict.status)
      end

      # The error-recovery render: no strategy result exists, so the evaluator
      # deliberately does not run (Core::Views::InitializeViewVars) and no
      # identity is projected. A session that names a customer is reported as
      # `unavailable` — this response cannot say whether it is still valid —
      # and anything else as `anonymous`. Replaces the client-side inference
      # from the raw session with a server statement.
      #
      # @param session [#[], nil] the raw Rack session
      # @return [String] UNAVAILABLE or ANONYMOUS
      def without_verdict(session)
        named = session.respond_to?(:[]) && !session['external_id'].to_s.empty?
        named ? UNAVAILABLE : ANONYMOUS
      end
    end
  end
end

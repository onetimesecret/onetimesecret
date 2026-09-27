# lib/onetime/session/auth_status.rb
#
# frozen_string_literal: true

require_relative 'customer_session_evaluator'

module Onetime
  # The bootstrap payload's `auth_status` (#4462): the public projection of a
  # CustomerSessionEvaluator verdict, emitted by HTML hydration and
  # `GET /bootstrap/me`.
  #
  # Four values go on the wire. `checking` exists only in the client, which
  # uses it before it has any server statement.
  #
  #   authenticated  The verdict is authenticated; `cust` is present.
  #   mfa_pending    First factor passed, second factor outstanding.
  #   anonymous      No customer session — including one the evaluator
  #                  REJECTED. Bootstrap states identity, not diagnosis: the
  #                  rejection reason reaches logs and the API `code`, never a
  #                  public payload.
  #   unavailable    The session could not be verified. The client must not
  #                  read this as a sign-out.
  #
  # `authenticated` and `awaiting_mfa` stay in the payload as compatibility
  # projections of this value (Core::Views::AuthenticationSerializer derives
  # them from it), so the three fields cannot disagree. Every mapping here can
  # only withhold: nothing but an authenticated verdict yields `authenticated`.
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
      # and anything else as `anonymous`. Replaces the client-side
      # `had_valid_session` inference with a server statement.
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

# apps/api/colonel/logic/destructive_action.rb
#
# frozen_string_literal: true

require 'rack/utils'

module ColonelAPI
  module Logic
    # Shared guard for destructive and sensitive colonel verbs (epic #4323).
    #
    # Included into ColonelAPI::Logic::Base, so every colonel logic class HAS these
    # methods; only the classes named in ColonelAPI::DestructiveActions CALL them.
    # Declare-and-call rather than inherit-and-override: none of the ~86 concrete
    # classes call `super` in raise_concerns, so a base-class hook would be silently
    # skipped.
    #
    # GUARD ORDER CONTRACT — inside raise_concerns, always:
    #   1. verify_one_of_roles!(colonel: true)
    #   2. resolve the target; existing 404 / 422 / enum / allowlist guards
    #   3. guard_destructive_action!(...)      <- elevation, then confirmation
    #   4. per-verb interlocks (self-target, last-colonel, sole-owner)
    #   5. charge_destructive_budget!          <- tier 1 only, ALWAYS LAST
    #
    # Interlocks run AFTER proof so their 422s do not disclose "is this the last
    # colonel" / "is this handle mine" to a caller who has proven nothing but
    # possession of the cookie. The destructive budget is charged LAST so only
    # requests that are about to execute consume it — otherwise the designed
    # attempt/elevate/retry flow double-charges every operator action, and an
    # attacker can pre-emptively lock the real operator out with cheap 403s.
    # Volume is still bounded by the broad colonel:mutation bucket charged in
    # ColonelAPI::Logic::Base#initialize.
    #
    # PREVIEW EXEMPTION: verbs with a dry_run flag call ALL of 3-5 only on the
    # apply path (`return if dry_run` before the guard). A preview writes nothing,
    # so gating it would break the console's preview-then-apply flow for no benefit
    # — the same asymmetry delete_organization.rb already documents for its
    # guardrail statuses. This is asserted, not assumed: see
    # try/unit/colonel/dry_run_side_effects_try.rb.
    module DestructiveAction
      MAX_CONFIRM_LENGTH = 255
      TRUTHY_VALUES      = %w[true 1 yes on].freeze

      # The only two tiers guard_destructive_action! accepts. A typo'd tier would
      # silently drop elevation and the destructive budget once P3/P5 land, so it
      # is a 500 here rather than a quiet downgrade.
      GUARD_TIERS = [:destructive, :sensitive].freeze

      # Hoisted from the ten colonel classes that each defined their own (two of
      # which disagreed: purge_dlq/replay_dlq accepted only %w[1 true yes] and did
      # not strip). This is the widest of the existing forms.
      def truthy?(value)
        TRUTHY_VALUES.include?(value.to_s.strip.downcase)
      end

      # The supplied confirmation token, or ''.
      #
      # Read from strategy metadata (the X-OTS-Confirm header, see
      # ColonelAPI::AuthStrategies::SessionAuthStrategy), NOT from params: a query
      # parameter would put target emails into access logs and browser history,
      # and a DELETE body is not reliably parsed in this stack.
      #
      # Deliberately NOT run through sanitize_identifier: the token is frequently an
      # email address, and sanitize_identifier strips '@' and '.' (the exact bug
      # AccountIdentifier#sanitize_account_identifier exists to fix). It is only ever
      # compared against a known-good expected string — never interpolated into a
      # Redis key, a query, or a log line — so a length cap is the whole hygiene
      # requirement.
      #
      # @return [String]
      def supplied_confirmation
        strategy_result&.metadata&.dig(:confirm_token).to_s.strip[0, MAX_CONFIRM_LENGTH].to_s
      end

      # Reject unless the caller echoed the expected token.
      #
      # @param expected [String] exact token; a blank expected value is a programming
      #   error and raises Onetime::GuardMisconfigured (500) rather than admitting
      #   the request.
      # @param subject [String] human phrase naming WHAT to send, e.g.
      #   'the account email address'. Never interpolate the expected value itself
      #   into the message for a caller who may not know it.
      # @param field [Symbol] the param the console should highlight.
      # @raise [Onetime::GuardMisconfigured] 500 when `expected` is blank
      # @raise [Onetime::ConfirmationRequired] 403 when the caller did not match
      # @return [true]
      def require_confirmation!(expected, subject:, field: :confirm)
        expected = expected.to_s.strip
        if expected.empty?
          OT.le "[DestructiveAction] blank expected confirmation token in #{self.class.name}"
          raise Onetime::GuardMisconfigured, "blank expected confirmation token (#{self.class.name})"
        end

        supplied = supplied_confirmation
        return true if !supplied.empty? && Rack::Utils.secure_compare(supplied, expected)

        # Identical rejection whether the header was absent or merely wrong: no
        # oracle on which half the caller got right.
        raise Onetime::ConfirmationRequired.new(
          "Confirmation required: re-send this request with the X-OTS-Confirm header set to #{subject}.",
          field: field,
        )
      end

      # Refuse unless the session holds a live, identity-matched step-up window
      # (#4327). No-op when elevation is disabled by config.
      #
      # Writes NO audit event: a Forbidden-family rejection is drivable on demand
      # by whoever holds the cookie, and the operator trail is count-capped with
      # no TTL. The window arithmetic and the identity binding live in
      # ColonelAPI::Logic::Colonel::Elevation.
      #
      # @raise [Onetime::ElevationRequired] 403
      def require_elevation!
        return unless elevation_enabled?
        return if elevated?

        raise Onetime::ElevationRequired.new(
          'Step-up authentication required. Re-authenticate to continue ' \
          "(POST /api/colonel/elevation), then retry within #{elevation_window / 60} minutes.",
          window: elevation_window,
        )
      end

      # Step 3 of the guard-order contract: elevation (tier 1 only), THEN
      # confirmation.
      #
      # Elevation first is deliberate: an unelevated caller must never learn
      # whether their confirmation-token guess was right (no confirmation
      # oracle), and the console prompts for sudo before the operator wastes
      # their typing. TIER 2 is deliberately not elevation-gated — those verbs
      # are reversible, and gating them would double the sudo prompts an
      # operator sees during routine triage.
      #
      # @param tier [Symbol] :destructive (TIER1) or :sensitive (TIER2)
      # @param confirm_with [String] the expected confirmation token
      # @param confirm_subject [String] human phrase for the error message
      # @param field [Symbol]
      def guard_destructive_action!(tier:, confirm_with:, confirm_subject:, field: :confirm)
        unless GUARD_TIERS.include?(tier)
          OT.le "[DestructiveAction] unknown tier #{tier.inspect} in #{self.class.name}"
          raise Onetime::GuardMisconfigured, "unknown destructive-action tier #{tier.inspect} (#{self.class.name})"
        end

        require_elevation! if tier == :destructive
        require_confirmation!(confirm_with, subject: confirm_subject, field: field)
      end

      # Step 5. Separate call, ALWAYS the last line of raise_concerns, tier 1 only.
      # Two calls rather than one is deliberate: it is greppable, and
      # spec/unit/colonel/destructive_actions_spec.rb asserts both are present in
      # every TIER 1 class.
      def charge_destructive_budget!
        # P5 (#4329) inserts: enforce_colonel_destructive_limit!(cust&.extid)
      end

      # Human-meaningful, non-URL identifier for an account. The extid fallback
      # keeps the expected token non-blank by construction (a blank one is a 500).
      def account_confirm_token(customer)
        email = customer.respond_to?(:email) ? customer.email.to_s.strip : ''
        email.empty? ? customer.extid.to_s : email
      end

      # Human-meaningful, non-URL identifier for an organization.
      def org_confirm_token(org)
        name = org.respond_to?(:display_name) ? org.display_name.to_s.strip : ''
        name.empty? ? org.extid.to_s : name
      end
    end
  end
end

# apps/api/colonel/logic/base.rb
#
# frozen_string_literal: true

# Colonel API Logic Base Class
#
# Extends V2 logic with modern API patterns for Colonel API.
#
# Key differences from v2:
# 1. Native JSON types (numbers, booleans, null) instead of string-serialized values
# 2. Pure REST semantics - no "success" field (use HTTP status codes)
# 3. Modern naming - "user_id" instead of "custid"
#
# Colonel API uses same modern conventions as v3 API for consistency.

require 'onetime/logic/base'
require 'onetime/application/authorization_policies'
require 'onetime/security/colonel_rate_limiter'

require_relative '../destructive_actions'
require_relative 'colonel/elevation'
require_relative 'destructive_action'

module ColonelAPI
  module Logic
    # ## The shared seam for the colonel hardening guards (epic #4323)
    #
    # {ColonelAPI::Logic::DestructiveAction} is included here, so every colonel
    # logic class HAS the guards; only the classes named in
    # {ColonelAPI::DestructiveActions} CALL them. Which classes those are — and
    # which mutating verbs are deliberately un-gated — is committed data in
    # `apps/api/colonel/destructive_actions.rb`, not prose.
    #
    # GUARD ORDER CONTRACT — inside raise_concerns, always, in this order:
    #
    #   1. verify_one_of_roles!(colonel: true)
    #   2. resolve the target; existing 404 / 422 / enum / allowlist guards
    #   3. guard_destructive_action!(...)      <- elevation (#4327), then
    #                                             confirmation (#4326)
    #   4. per-verb interlocks (self-target, last-colonel, sole-owner) (#4328)
    #   5. charge_destructive_budget!          <- tier 1 only, ALWAYS LAST (#4329)
    #
    # Reordering it re-opens an information oracle (interlock 422s answering
    # "is this the last colonel?" to a caller who proved nothing) or a
    # budget-exhaustion DoS (cheap rejected requests burning the real operator's
    # destructive allowance). Verbs with a `dry_run` preview run steps 3-5 on the
    # apply path only.
    class Base < Onetime::Logic::Base
      include Onetime::Application::AuthorizationPolicies
      # Elevation first: DestructiveAction#require_elevation! is written against
      # this module's window arithmetic (#4327).
      include ColonelAPI::Logic::Colonel::Elevation
      include ColonelAPI::Logic::DestructiveAction
      # The four colonel rate-limit buckets (#4329): the tight destructive one
      # step 5 charges through DestructiveAction#charge_destructive_budget!, the
      # broad mutation one #initialize below charges, the handle-resolve one the
      # two session reads charge, and the step-up one ElevateSession charges.
      include Onetime::Security::ColonelRateLimiter

      using Familia::Refinements::TimeLiterals

      # HTTP methods that can change state. PUT is here for the one PUT route
      # (`PUT /domains/:extid/configs/:kind`); PATCH is unused today and listed
      # so a future route is covered the day it appears.
      MUTATING_METHODS = %w[POST PUT PATCH DELETE].freeze

      # Charge the broad colonel-mutation bucket once per mutating request
      # (#4329, 120 / 300 s).
      #
      # HERE rather than in raise_concerns because none of the ~86 concrete
      # colonel classes call `super` in raise_concerns, so a base-class hook
      # there would be silently skipped; and the router has ALREADY enforced
      # role=colonel by the time a logic class is constructed, so `cust` is the
      # authenticated colonel. Self-gated on has_system_role? anyway, so this can
      # never charge an unauthenticated caller. This is the ONE deliberate
      # exception to "every authorization guard lives in raise_concerns" — it is
      # a budget charge, not an authorization decision.
      #
      # It is also the ONLY bucket charged before the guards run, and it is
      # deliberately coarse: it bounds request VOLUME. The tight destructive
      # bucket is charged LAST, after elevation and confirmation pass (see the
      # guard-order contract above), so an attacker holding the cookie cannot
      # burn the real operator's destructive budget with cheap 403s.
      #
      # Reads are deliberately NOT limited here: the console fetches several of
      # them on every screen and a limiter there would break the dashboard. The
      # two handle-resolving session reads are the one exception and charge
      # their own bucket explicitly (#4330).
      #
      # KNOWN GAP: process_params runs inside `super` and may raise first, so a
      # malformed-param flood is not charged. Accepted — such a request mutates
      # nothing.
      def initialize(strategy_result, params, locale = nil)
        super
        return unless mutating_colonel_request?

        enforce_colonel_mutation_limit!(cust.extid)
      end

      # Transform v2 response data to Colonel API format
      #
      # Colonel API changes (same as v3):
      # - Remove "success" field (use HTTP status codes)
      # - Rename "custid" to "user_id" (modern naming)
      #
      # @return [Hash] Colonel API-formatted response data
      def success_data
        # Get the v2 response data
        v2_data = super

        # Transform for Colonel API
        colonel_data = v2_data.dup

        # Remove success field (Colonel API uses HTTP status codes)
        colonel_data.delete(:success)
        colonel_data.delete('success')

        # Rename custid to user_id (modern naming)
        if colonel_data.key?(:custid)
          colonel_data[:user_id] = colonel_data.delete(:custid)
        elsif colonel_data.key?('custid')
          colonel_data['user_id'] = colonel_data.delete('custid')
        end

        colonel_data
      end

      private

      # Whether this request is a mutating one made by an authenticated colonel.
      #
      # The method arrives through StrategyResult#metadata (the colonel session
      # auth strategy puts it there) because logic classes never receive the Rack
      # request or env. A metadata hash without it — any caller that did not come
      # through the colonel router, including every bare `double(...)` in the
      # spec suites — reads as "not a mutation" and charges nothing, which is the
      # right answer for a caller the strategy never saw.
      #
      # Method first, role second: the method is a Hash lookup while the role
      # check touches the Customer model, so a read (or a non-HTTP caller) never
      # pays for it.
      def mutating_colonel_request?
        return false unless MUTATING_METHODS.include?(
          strategy_result&.metadata&.dig(:request_method).to_s.upcase,
        )

        has_system_role?('colonel')
      end
    end
  end
end

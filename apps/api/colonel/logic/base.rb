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

      using Familia::Refinements::TimeLiterals

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
    end
  end
end

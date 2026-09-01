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
require 'onetime/audit_reason'

module ColonelAPI
  module Logic
    class Base < Onetime::Logic::Base
      include Onetime::Application::AuthorizationPolicies
      include Onetime::AuditReason

      using Familia::Refinements::TimeLiterals

      # The OPTIONAL operator-supplied `reason` on a destructive verb (#4338),
      # read off the request and handed to the op as its `reason:` kwarg.
      #
      # ONE reader for every destructive colonel adapter, so the param name,
      # the sanitizer and the bound cannot drift between twelve endpoints. Two
      # passes on purpose: `sanitize_plain_text` strips HTML/entities and
      # normalizes whitespace (this is free operator text that lands in an
      # operator-facing console), and `normalize_reason` applies the audit
      # rule — blank means ABSENT, never `reason: ""`.
      #
      # The bound is {Onetime::AuditReason::MAX_LENGTH}, one under the audit
      # model's per-value truncation, so a reason accepted here is never
      # silently clipped in the trail.
      #
      # DELETE endpoints read this from the QUERY STRING; request bodies are
      # not reliably parsed across this stack (see DeleteOrganization's note).
      # `params` merges both, so this reader is the same on either verb.
      #
      # OPTIONAL for now (#4338 rolls out in two steps). When the flip to
      # REQUIRED happens, it happens here plus {Onetime::AuditReason} — not in
      # each adapter.
      #
      # @return [String, nil]
      def operator_reason_param
        normalize_reason(
          sanitize_plain_text(params['reason'], max_length: Onetime::AuditReason::MAX_LENGTH),
        )
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
    end
  end
end

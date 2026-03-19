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

module ColonelAPI
  module Logic
    class Base < Onetime::Logic::Base
      include Onetime::Application::AuthorizationPolicies

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

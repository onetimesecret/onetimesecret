# apps/api/domains/logic/base.rb
#
# frozen_string_literal: true

# Domains API Logic Base Class
#
# Extends V2 logic with modern API patterns for Domains API.
#
# Key differences from v2:
# 1. Native JSON types (numbers, booleans, null) instead of string-serialized values
# 2. Pure REST semantics - no "success" field (use HTTP status codes)
# 3. Modern naming - "user_id" instead of "custid"
#
# Domains API uses same modern conventions as v3 API for consistency.

require 'onetime/logic/base'

module DomainsAPI
  module Logic
    class Base < Onetime::Logic::Base
      # Transform v2 response data to Domains API format
      #
      # Domains API changes (same as v3):
      # - Remove "success" field (use HTTP status codes)
      # - Rename "custid" to "user_id" (modern naming)
      #
      # @return [Hash] Domains API-formatted response data
      def success_data
        # Get the v2 response data
        v2_data = super

        # Transform for Domains API
        domains_data = v2_data.dup

        # Remove success field (Domains API uses HTTP status codes)
        domains_data.delete(:success)
        domains_data.delete('success')

        # Rename custid to user_id (modern naming)
        if domains_data.key?(:custid)
          domains_data[:user_id] = domains_data.delete(:custid)
        elsif domains_data.key?('custid')
          domains_data['user_id'] = domains_data.delete('custid')
        end

        domains_data
      end
    end
  end
end

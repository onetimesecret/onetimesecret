# apps/api/account/logic/base.rb
#
# frozen_string_literal: true

# Account API Logic Base Class
#
# Extends V2 logic with modern API patterns for Account API.
#
# Key differences from v2:
# 1. Native JSON types (numbers, booleans, null) instead of string-serialized values
# 2. Pure REST semantics - no "success" field (use HTTP status codes)
# 3. Modern naming - "user_id" instead of "custid"
#
# Account API uses same modern conventions as v3 API for consistency.

require 'onetime/logic/base'

module AccountAPI
  module Logic
    class Base < Onetime::Logic::Base
      # Extract session ID for logging purposes
      def session_sid
        sess&.[]('sid') || sess&.[](:sid) || 'unknown'
      end

      # Transform v2 response data to Account API format
      #
      # Account API changes (same as v3):
      # - Remove "success" field (use HTTP status codes)
      # - Rename "custid" to "user_id" (modern naming)
      #
      # @return [Hash] Account API-formatted response data
      def success_data
        # Get the v2 response data
        v2_data = super

        # Transform for Account API
        account_data = v2_data.dup

        # Remove success field (Account API uses HTTP status codes)
        account_data.delete(:success)
        account_data.delete('success')

        # Rename custid to user_id (modern naming)
        if account_data.key?(:custid)
          account_data[:user_id] = account_data.delete(:custid)
        elsif account_data.key?('custid')
          account_data['user_id'] = account_data.delete('custid')
        end

        account_data
      end
    end
  end
end

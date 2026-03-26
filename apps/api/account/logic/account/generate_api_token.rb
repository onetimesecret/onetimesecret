# apps/api/account/logic/account/generate_api_token.rb
#
# frozen_string_literal: true

module AccountAPI::Logic
  module Account
    # Generate API Token
    #
    # @api Regenerates the authenticated user's API token and returns
    #   the new token value. Requires an active session; anonymous
    #   users are rejected.
    class GenerateAPIToken < AccountAPI::Logic::Base
      SCHEMAS = { response: 'apiToken' }.freeze

      attr_reader :apitoken, :greenlighted

      def process_params
        OT.ld "[GenerateAPIToken#process_params] params: #{params.inspect}"
      end

      def raise_concerns
        # Requires both session authentication AND non-anonymous user.
        # This endpoint is session-only (no BasicAuth) to ensure the user
        # has an active browser session, not just valid API credentials.
        session_authenticated = @sess['authenticated'] == true
        unless session_authenticated
          raise_form_error('Session authentication required', field: :session, error_type: :unauthorized)
        end

        verify_authenticated!
      end

      def process
        @greenlighted = true
        @apitoken     = cust.regenerate_apitoken

        success_data
      end

      private

      # The data returned from this method is passed back to the client.
      def success_data
        { record: { apitoken: apitoken, active: true } }
      end
    end
  end
end

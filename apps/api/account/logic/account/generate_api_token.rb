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
        authenticated = @sess['authenticated'] == true
        return unless !authenticated || cust.anonymous?

        raise_form_error "Sorry, we don't support that"
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

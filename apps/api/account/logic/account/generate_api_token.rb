# apps/api/account/logic/account/generate_api_token.rb

module AccountAPI::Logic
  module Account
    class GenerateAPIToken < AccountAPI::Logic::Base
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

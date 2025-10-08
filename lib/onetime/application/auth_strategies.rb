# lib/onetime/application/auth_strategies.rb
#
# Shared authentication strategy helpers for Onetime applications.
# Individual applications register their own strategies using these helpers.

module Onetime
  module Application
    module AuthStrategies
      # Shared helper methods for authentication strategies
      module Helpers
        # Loads customer from session if authenticated
        #
        # @param session [Hash] Rack session
        # @return [Onetime::Customer, nil] Customer if found, nil otherwise
        def load_customer_from_session(session)
          return nil unless session
          return nil unless session['authenticated'] == true

          identity_id = session['identity_id']
          return nil unless identity_id.to_s.length > 0

          Onetime::Customer.load(identity_id)
        rescue StandardError => ex
          OT.le "[auth_strategy] Failed to load customer: #{ex.message}"
          nil
        end

        # Builds standard metadata hash from env
        #
        # @param env [Hash] Rack environment
        # @param additional [Hash] Additional metadata to merge
        # @return [Hash] Metadata hash
        def build_metadata(env, additional = {})
          {
            ip: env['REMOTE_ADDR'],
            user_agent: env['HTTP_USER_AGENT']
          }.merge(additional)
        end
      end
    end
  end
end

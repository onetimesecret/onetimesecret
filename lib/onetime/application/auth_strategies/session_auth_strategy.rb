# lib/onetime/application/auth_strategies/session_auth_strategy.rb
#
# frozen_string_literal: true

#
# Authenticated strategy - requires valid session with authenticated customer.
#
# Routes: auth=sessionauth
# Access: Authenticated users only
# User: Authenticated Customer
# Roles: Provides customer role(s) for Otto's role-based authorization (role= option)
#
# @see Onetime::Application::AuthStrategies

require_relative 'base_session_auth_strategy'

module Onetime
  module Application
    module AuthStrategies
      class SessionAuthStrategy < BaseSessionAuthStrategy
        @auth_method_name = 'sessionauth'

        protected

        def additional_metadata(cust)
          # Provide roles as array for Otto's role= parameter support
          # Otto's RouteAuthWrapper#extract_user_roles looks for metadata[:user_roles]
          { user_roles: [cust.role.to_s] }
        end
      end
    end
  end
end

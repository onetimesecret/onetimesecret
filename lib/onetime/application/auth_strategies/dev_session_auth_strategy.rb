# lib/onetime/application/auth_strategies/dev_session_auth_strategy.rb
#
# frozen_string_literal: true

#
# Development-only Session Auth strategy for browser-based dev workflows.
#
# Routes: auth=devsessionauth
# Access: Authenticated dev_* users only (session-based)
# User: Ephemeral Customer with dev_* prefixed email
#
# ## Configuration
#
# Enable via environment variable (recommended):
#
#   DEV_SESSION_AUTH=true bundle exec thin start
#
# Or in config YAML with ERB:
#
#   development:
#     devsessionauth: <%= ENV['DEV_SESSION_AUTH'] == 'true' %>
#
# ## Flow
#
# 1. User logs in via dev login endpoint (which creates session with dev_* identity)
# 2. Routes protected by auth=devsessionauth validate the session belongs to a dev user
# 3. Session-based auth enables browser testing with cookies
#
# ## Security
#
# - BLOCKED in production (raises SecurityError on registration attempt)
# - Validates customer email starts with dev_ prefix
# - Generic errors prevent information disclosure
#
# @see DevBasicAuthStrategy for API/curl-based dev auth
# @see https://github.com/onetimesecret/onetimesecret/issues/2735

require_relative 'base_session_auth_strategy'

module Onetime
  module Application
    module AuthStrategies
      class DevSessionAuthStrategy < BaseSessionAuthStrategy
        # Prefix required for dev usernames (same as DevBasicAuthStrategy)
        DEV_PREFIX = 'dev_'

        @auth_method_name = 'dev_session_auth'

        class << self
          # Guard: prevent registration in production
          def production_guard!
            return unless OT.production?

            raise SecurityError,
              '[DEV_AUTH_BLOCKED] DevSessionAuthStrategy cannot be registered in production'
          end
        end

        def authenticate(env, requirement)
          # Runtime guard (belt + suspenders with registration guard)
          if OT.production?
            return failure('[DEV_AUTH_BLOCKED] Development auth disabled in production')
          end

          # Delegate all session validation and customer loading to parent
          super
        end

        protected

        # Check if customer is a dev user based on email prefix
        #
        # @param cust [Onetime::Customer] Customer to check
        # @return [Boolean] true if customer email starts with dev_
        def dev_user?(cust)
          cust.email.to_s.start_with?(DEV_PREFIX)
        end

        # Validate the customer is a dev user (email must start with dev_ prefix)
        #
        # @param cust [Onetime::Customer] Authenticated customer
        # @param env [Hash] Rack environment
        # @return [Otto::Security::Authentication::AuthFailure, nil] Failure if not dev user
        def additional_checks(cust, _env)
          return failure('[DEV_USER_REQUIRED] Session does not belong to a dev user') unless dev_user?(cust)

          nil
        end

        # Add dev-specific metadata to the auth result
        #
        # @param cust [Onetime::Customer] Authenticated customer
        # @return [Hash] Metadata including dev_user flag and user roles
        def additional_metadata(cust)
          {
            user_roles: [cust.role.to_s],
            dev_user: true,
          }
        end

        def log_success(cust)
          OT.ld "[dev_session_auth] Authenticated dev user '#{cust.custid}'"
        end
      end
    end
  end
end

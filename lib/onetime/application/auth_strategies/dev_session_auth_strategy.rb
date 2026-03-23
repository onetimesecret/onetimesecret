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

        def authenticate(env, _requirement)
          # Runtime guard (belt + suspenders with registration guard)
          if OT.production?
            return failure('[DEV_AUTH_BLOCKED] Development auth disabled in production')
          end

          # Delegate to parent for basic session validation
          session = env['rack.session']
          return failure('[SESSION_MISSING] No session available') unless session

          unless session['authenticated'] == true
            return failure('[SESSION_NOT_AUTHENTICATED] Not authenticated')
          end

          external_id = session['external_id']
          if external_id.to_s.empty?
            return failure('[IDENTITY_MISSING] No identity in session')
          end

          # Load customer
          cust = Onetime::Customer.load_by_extid_or_email(external_id)
          return failure('[CUSTOMER_NOT_FOUND] Customer not found') unless cust

          # Validate this is a dev user (email must start with dev_)
          unless dev_user?(cust)
            return failure('[DEV_USER_REQUIRED] Session does not belong to a dev user')
          end

          # Perform additional checks (role, permissions, etc.)
          check_result = additional_checks(cust, env)
          return check_result if check_result.is_a?(Otto::Security::Authentication::AuthFailure)

          log_success(cust)

          # Load organization context (dev users may still have org associations)
          org_context = load_organization_context(cust, session, env)

          # Build metadata with dev-specific flags
          metadata_hash = build_metadata(env, additional_metadata(cust)).merge(
            organization_context: org_context,
            dev_user: true,
          )

          success(
            session: session,
            user: cust,
            auth_method: self.class.auth_method_name,
            **metadata_hash,
          )
        end

        protected

        # Check if customer is a dev user based on email prefix
        #
        # @param cust [Onetime::Customer] Customer to check
        # @return [Boolean] true if customer email starts with dev_
        def dev_user?(cust)
          cust.email.to_s.start_with?(DEV_PREFIX)
        end

        def additional_metadata(cust)
          { user_roles: [cust.role.to_s] }
        end

        def log_success(cust)
          OT.ld "[dev_session_auth] Authenticated dev user '#{cust.custid}'"
        end
      end
    end
  end
end

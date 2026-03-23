# lib/onetime/application/auth_strategies/basic_auth_strategy.rb
#
# frozen_string_literal: true

#
# Basic auth strategy - HTTP Basic Authentication.
#
# Routes: auth=basicauth
# Access: Valid API credentials via Authorization header
# User: Customer associated with API credentials
#
# Security: Uses constant-time comparison for both username and API key
# to prevent timing attacks that could enumerate valid usernames.
#
# @see Onetime::Application::AuthStrategies

require_relative 'helpers'

module Onetime
  module Application
    module AuthStrategies
      class BasicAuthStrategy < Otto::Security::AuthStrategy
        include Helpers
        include Onetime::Application::OrganizationLoader

        @auth_method_name = 'basic_auth'

        class << self
          attr_reader :auth_method_name
        end

        def authenticate(env, _requirement)
          # Extract credentials from Authorization header
          auth_header = env['HTTP_AUTHORIZATION']
          return failure('[AUTH_HEADER_MISSING] No authorization header') unless auth_header

          # Parse Basic auth
          unless auth_header.start_with?('Basic ')
            return failure('[AUTH_TYPE_INVALID] Invalid authorization type')
          end

          # Decode credentials
          encoded          = auth_header.sub('Basic ', '')
          decoded          = Base64.decode64(encoded)
          username, apikey = decoded.split(':', 2)

          return failure('[CREDENTIALS_FORMAT_INVALID] Invalid credentials format') unless username && apikey

          # Load customer by custid (may be nil)
          cust = Onetime::Customer.load_by_extid_or_email(username)

          # Timing attack mitigation:
          # To prevent username enumeration via timing analysis, we ensure that
          # authentication takes the same amount of time whether the user exists or not.
          #
          # Strategy:
          # 1. Use a dummy customer with a real BCrypt hash when user doesn't exist
          # 2. Always perform BCrypt password comparison (expensive operation)
          # 3. Both paths execute identical cryptographic operations
          #
          # The dummy customer has a pre-computed BCrypt hash, so passphrase?()
          # performs the same ~280ms BCrypt comparison for both existing and
          # non-existing users, making timing analysis ineffective.
          target_cust = cust || Onetime::Customer.dummy

          # Validate API key using constant-time comparison (apitoken?)
          valid_credentials = target_cust.apitoken?(apikey)

          # Only succeed if we have a real customer AND valid credentials
          if cust && valid_credentials
            OT.ld "[onetime_basic_auth] Authenticated '#{cust.objid}' via API key"

            # Load organization context for API key auth.
            # Use the real Rack session if present; nil for stateless calls.
            # OrganizationLoader guards session access with `if session`.
            session     = env['rack.session']
            org_context = load_organization_context(cust, session, env)

            # Build complete metadata hash, then splat it into success()
            metadata_hash = build_metadata(env, { auth_type: 'basic' }).merge(
              organization_context: org_context,
            )

            success(
              session: session,  # nil when no Rack session middleware (stateless),
              # SecureSessionHash when session middleware is present.
              # Otto's RouteAuthWrapper skips env['rack.session'] overwrite
              # when result.session is nil/falsy, preserving the original.
              # Don't fabricate a fallback {} here - rack-session's
              # commit_session calls .options on the session object.
              user: cust,
              auth_method: self.class.auth_method_name,
              **metadata_hash,
            )
          else
            # Return generic error for both cases:
            # 1. User doesn't exist (cust is nil)
            # 2. Invalid credentials (valid_credentials is false)
            # The timing is identical in both cases due to our mitigation strategy
            failure('[CREDENTIALS_INVALID] Invalid credentials')
          end
        end
      end
    end
  end
end

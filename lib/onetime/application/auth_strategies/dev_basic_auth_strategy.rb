# lib/onetime/application/auth_strategies/dev_basic_auth_strategy.rb
#
# frozen_string_literal: true

#
# Development-only Basic Auth strategy with auto-provisioning.
#
# Routes: auth=devbasicauth
# Access: dev_* prefixed credentials only
# User: Auto-created ephemeral Customer with 20-hour TTL
#
# ## Configuration
#
# Enable via environment variable (recommended):
#
#   DEV_BASIC_AUTH=true bundle exec thin start
#
# Or in config YAML with ERB:
#
#   development:
#     devbasicauth: <%= ENV['DEV_BASIC_AUTH'] == 'true' %>
#
# ## Usage
#
#   curl -u dev_alice:dev_secretkey123 http://localhost:7143/api/v2/status
#
# The user `dev_alice@dev.local` is auto-created on first request and
# expires after 20 hours. Subsequent requests reuse the same user.
#
# ## Security
#
# - BLOCKED in production (raises SecurityError on registration attempt)
# - Requires dev_ prefix on BOTH username AND apikey
# - Ephemeral users auto-expire via Redis TTL, reducing data accumulation
# - Generic "unavailable" errors prevent username enumeration
#
# @see Onetime::Application::AuthStrategies
# @see https://github.com/onetimesecret/onetimesecret/issues/2735

require_relative 'basic_auth_strategy'

module Onetime
  module Application
    module AuthStrategies
      class DevBasicAuthStrategy < BasicAuthStrategy
        # 20 hours in seconds
        DEV_CUSTOMER_TTL = 20 * 60 * 60

        # Prefix required for all dev credentials
        DEV_PREFIX = 'dev_'

        @auth_method_name = 'dev_basic_auth'

        class << self
          # Guard: prevent registration in production
          def production_guard!
            return unless OT.production?

            raise SecurityError,
              '[DEV_AUTH_BLOCKED] DevBasicAuthStrategy cannot be registered in production'
          end
        end

        def authenticate(env, _requirement)
          # Runtime guard (belt + suspenders with registration guard)
          if OT.production?
            return failure('[DEV_AUTH_BLOCKED] Development auth disabled in production')
          end

          # Extract and parse Basic Auth credentials (inherited from BasicAuthStrategy)
          credentials = parse_basic_auth_credentials(env)
          return credentials if credentials.is_a?(Otto::Security::Authentication::AuthFailure)

          username, apikey = credentials

          # Validate dev_ prefix on BOTH username and apikey
          unless valid_dev_credentials?(username, apikey)
            return failure('[DEV_PREFIX_REQUIRED] Development credentials must use dev_ prefix')
          end

          # Attempt to load or create the dev user
          cust = find_or_create_dev_customer(username, apikey)

          # Timing attack mitigation:
          # Use dummy customer when cust is nil to ensure BCrypt comparison
          # always runs, preventing timing-based enumeration of valid dev usernames.
          target_cust       = cust || Onetime::Customer.dummy
          valid_credentials = target_cust.apitoken?(apikey)

          # Only succeed if we have a real customer AND valid credentials
          unless cust && valid_credentials
            return failure('[CREDENTIALS_INVALID] Invalid credentials')
          end

          OT.ld "[dev_basic_auth] Authenticated dev user '#{cust.custid}'"

          session     = env['rack.session']
          org_context = load_organization_context(cust, session, env)

          metadata_hash = build_metadata(env, { auth_type: 'dev_basic' }).merge(
            organization_context: org_context,
            dev_user: true,
            ttl_seconds: DEV_CUSTOMER_TTL,
          )

          success(
            session: session,
            user: cust,
            auth_method: self.class.auth_method_name,
            **metadata_hash,
          )
        end

        private

        def valid_dev_credentials?(username, apikey)
          username.to_s.start_with?(DEV_PREFIX) && apikey.to_s.start_with?(DEV_PREFIX)
        end

        # Find existing dev customer or create a new ephemeral one
        #
        # @param username [String] dev_* prefixed username (used as email)
        # @param apikey [String] dev_* prefixed API key
        # @return [Customer, nil] the customer or nil if creation failed
        def find_or_create_dev_customer(username, apikey)
          # Use username as a synthetic email for dev users
          dev_email = "#{username}@dev.local"

          existing = Onetime::Customer.find_by_email(dev_email)
          return existing if existing

          # Create new ephemeral dev customer
          create_ephemeral_customer(dev_email, apikey)
        rescue Familia::RecordExistsError
          # Race condition: another request created it concurrently.
          # Retry lookup with validation to handle partial creation failures.
          cust = Onetime::Customer.find_by_email(dev_email)
          if cust&.exists?
            OT.ld "[dev_basic_auth] Race condition resolved for #{dev_email}"
            cust
          else
            OT.le "[dev_basic_auth] RecordExistsError but customer not found: #{dev_email}"
            nil
          end
        rescue StandardError => ex
          OT.le "[dev_basic_auth] Failed: #{ex.class}: #{ex.message}"
          nil
        end

        # Create a new dev customer with TTL expiration
        #
        # @param email [String] synthetic email (dev_*@dev.local)
        # @param apikey [String] API key to set
        # @return [Customer] the created customer
        def create_ephemeral_customer(email, apikey)
          OT.ld "[dev_basic_auth] Creating ephemeral dev customer: #{email}"

          cust = Onetime::Customer.create!(
            email: email,
            role: 'customer',
          )

          # Set the API token (fast writer, then save)
          cust.apitoken = apikey
          cust.save

          # Set TTL on the customer record for auto-cleanup
          # Familia::Horreum stores data in Redis hash, we expire the key
          cust.update_expiration(expiration: DEV_CUSTOMER_TTL)

          Onetime.auth_logger.info 'Created ephemeral dev customer',
            {
              email: email,
              ttl_hours: DEV_CUSTOMER_TTL / 3600,
              action: 'dev_create',
            }

          cust
        end
      end
    end
  end
end

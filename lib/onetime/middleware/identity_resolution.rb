# lib/onetime/middleware/identity_resolution.rb

require 'logger'
require 'rack/request'

module Onetime
  module Middleware
    # Identity Resolution Middleware for OneTimeSecret
    #
    # This middleware provides a flexible identity resolution layer that
    # bridges between the basic (e.g. Redis) and advanced authentication
    # services (e.g., Advanced with PostgreSQL/SQLite).
    #
    # ### Usage
    #
    # ```ruby
    # use Onetime::Middleware::IdentityResolution
    # ```
    #
    # The middleware sets the following env variables:
    # - `env['identity.resolved']` - The resolved identity object (Customer instance)
    # - `env['identity.source']` - Source of identity ('advanced', 'basic', 'anonymous')
    # - `env['identity.authenticated']` - Boolean authentication status
    # - `env['identity.metadata']` - Additional metadata about the identity
    #
    # ### Performance Optimization
    #
    # **IMPORTANT**: To prevent duplicate customer lookups per request, downstream
    # code should always use `env['identity.resolved']` instead of calling
    # `Customer.load()` or `Customer.find_by_extid()` directly.
    #
    # Good:
    # ```ruby
    # customer = env['identity.resolved']
    # authenticated = env['identity.authenticated']
    # ```
    #
    # Bad (causes duplicate lookup):
    # ```ruby
    # customer = Onetime::Customer.find_by_extid(session['external_id'])  # Already loaded by middleware!
    # ```
    #
    class IdentityResolution
      attr_reader :logger

      def initialize(app, logger: nil)
        @app    = app
        @logger = logger || default_logger
      end

      def call(env)
        request = Rack::Request.new(env)

        # Resolve identity from available sources
        identity = resolve_identity(request, env)

        # Store resolved identity in environment for downstream code to use
        # IMPORTANT: Downstream code should use env['identity.resolved'] instead of
        # calling Customer.load() directly to avoid duplicate lookups per request
        env['identity.resolved']      = identity[:user]
        env['identity.source']        = identity[:source]
        env['identity.authenticated'] = identity[:authenticated]
        env['identity.metadata']      = identity[:metadata]

        dmsg = identity.map { |k,v| format('%s=%s', k, v)}.join(' ')
        logger.debug "[IdentityResolution] Resolved #{dmsg}"

        @app.call(env)
      end

      private

      def resolve_identity(request, env)
        # Check authentication mode (basic vs advanced)
        auth_mode = detect_auth_mode

        case auth_mode
        when 'advanced'
          # Try Advanced session first
          advanced_identity = resolve_advanced_identity(request, env)
          return advanced_identity if advanced_identity[:user]
        when 'basic'
          # Use basic (Valkey/Redis-only) authentication
          basic_identity = resolve_basic_identity(request, env)
          return basic_identity if basic_identity[:user]
        end

        # Default to anonymous user
        resolve_anonymous_identity(request, env)
      end

      def resolve_advanced_identity(_request, env)
          # Get session from Valkey/Redis session middleware
          session = env['rack.session']

          return no_identity unless session

          # Check for Advanced authentication markers
          return no_identity unless advanced_authenticated?(session)

          # Lookup customer by derived extid
          customer = Onetime::Customer.find_by_extid(session['account_external_id'])
          return no_identity unless customer

          {
            user: build_advanced_user(customer, session),
            source: 'advanced',
            authenticated: true,
            metadata: {
              customer_id: customer.objid,
              external_id: customer.extid,
              account_id: session['account_id'],
              auth_method: 'advanced',
              authenticated_at: session['authenticated_at'],
              expires_at: session['authenticated_at'] ? session['authenticated_at'] + 86_400 : nil,
            },
          }
      rescue StandardError => ex
          logger.error "[IdentityResolution] Advanced identity error: #{ex.message}"
          no_identity
      end

      def resolve_external_identity(request, _env)
          # Extract session token from cookie or header
          token = extract_auth_token(request)
          return no_identity unless token

          # Validate token with external auth service
          auth_response = validate_with_external_service(token)

          if auth_response && auth_response[:valid]
            {
              user: build_external_user(auth_response[:user_data]),
              source: 'external',
              authenticated: true,
              metadata: {
                token: token,
                expires_at: auth_response[:expires_at],
                features: auth_response[:features] || [],
              },
            }
          else
            logger.debug '[IdentityResolution] External auth validation failed'
            no_identity
          end
      rescue StandardError => ex
          logger.error "[IdentityResolution] External auth error: #{ex.message}"
          no_identity
      end

      def resolve_basic_identity(request, env)
        # Use Rack::Session from middleware
        session = env['rack.session']

        # Don't require external_id - just check authenticated flag
        return no_identity unless session && session['authenticated'] == true

        # Check session expiry
        if session['authenticated_at']
          max_age = Onetime.auth_config.session['expire_after'] || 86_400
          age = Familia.now.to_i - session['authenticated_at'].to_i
          return no_identity if age >= max_age
        end

        # Return identity WITHOUT loading Customer from Redis
        # Controllers will lazy-load via SessionHelpers#current_customer when needed
        {
          user: nil,  # Don't load here - let controllers use SessionHelpers
          source: 'basic',
          authenticated: true,
          metadata: {
            external_id: session['external_id'],
            email: session['email'],
            session_id: session.id&.private_id,
            expires_at: session['authenticated_at'] ? session['authenticated_at'] + 86_400 : nil,
            ip_address: session['ip_address'] || request.ip,
          },
        }
      end

      def resolve_anonymous_identity(request, _env)
        {
          user: build_anonymous_user(request),
          source: 'anonymous',
          authenticated: false,
          metadata: {
            ip_address: request.ip,
            user_agent: request.user_agent,
          },
        }
      end

      def extract_auth_token(request)
        # Try Authorization header first (for API requests)
        auth_header = request.get_header('HTTP_AUTHORIZATION')
        if auth_header&.start_with?('Bearer ')
          return auth_header.sub('Bearer ', '')
        end

        # Try session cookie (for web requests)
        request.cookies['ots_auth_token'] || request.cookies['sess']
      end

      def load_customer_from_session(session)
        # Use existing Customer model to load by external_id
        return nil unless session['external_id']

        begin
          # Load Onetime::Customer if not already loaded
          #
          # TODO: This should be in lib/onetime if it's going to refer to
          # a Onetime model.
          require_relative '../onetime/models' unless defined?(Onetime::Customer)

          Onetime::Customer.find_by_extid(session['external_id'])
        rescue StandardError => ex
          logger.error "[IdentityResolution] Could not load customer: #{ex.message}"
          nil
        end
      end

      def validate_with_external_service(_token)
        # This would make an HTTP request to the Advanced service
        # For now, return a placeholder structure

        service_url = external_auth_config['service_url']
        return nil unless service_url

        # TODO: Implement actual HTTP call to auth service
        # Example:
        # response = HTTP.post("#{service_url}/validate", json: { token: token })
        # JSON.parse(response.body)

        nil # Placeholder
      end

      def build_advanced_user(customer, _session)
        # Build user object from Advanced-authenticated customer
        customer
      end

      def build_basic_user(customer, _session)
        # Return the customer object directly
        # Session metadata is already available in identity[:metadata]
        customer
      end

      def build_anonymous_user(_request)
        # Return static, frozen anonymous customer
        Onetime::Customer.anonymous
      end

      def advanced_authenticated?(session)
        return false unless session['authenticated_at']
        return false unless session['external_id'] || session['account_id']

        # Check session age against configured expiry
        max_age = Onetime.auth_config.session['expire_after'] || 86_400
        age     = Familia.now.to_i - session['authenticated_at'].to_i
        age < max_age
      end

      def detect_auth_mode
        Onetime.auth_config.mode
      end

      def external_auth_enabled?
        config = external_auth_config
        config && config['enabled'] == true
      end

      def external_auth_config
        return @external_auth_config if defined?(@external_auth_config)

        @external_auth_config = if defined?(OT) && OT.respond_to?(:conf)
          OT.conf.dig('site', 'authentication', 'external') || {}
        else
          {}
        end
      end

      def no_identity
        {
          user: nil,
          source: nil,
          authenticated: false,
          metadata: {},
        }
      end

      def default_logger
        Onetime.http_logger
      end
    end
  end
end

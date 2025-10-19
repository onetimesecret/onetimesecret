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
    # customer = Onetime::Customer.load(session['identity_id'])  # Already loaded by middleware!
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

        logger.debug "[IdentityResolution] Resolved identity from #{identity[:source]}"

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
          # Use basic (Redis-only) authentication
          basic_identity = resolve_basic_identity(request, env)
          return basic_identity if basic_identity[:user]
        end

        # Default to anonymous user
        resolve_anonymous_identity(request, env)
      end

      def resolve_advanced_identity(_request, env)
          # Get session from Redis session middleware
          session = env['rack.session']
          logger.debug "[IdentityResolution] Advanced - Session: #{session.class}, keys: #{session.keys.join(', ') rescue 'none'}"
          logger.debug "[IdentityResolution] Advanced - authenticated=#{session['authenticated']}, account_external_id=#{session['account_external_id']}"

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
              account_id: session['advanced_account_id'],
              tenant_id: customer.primary_org_id,
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
        return no_identity unless session && session['identity_id']

        begin
          # Load customer using identity_id from session
          customer = load_customer_from_session(session)
          return no_identity unless customer

          {
            user: build_basic_user(customer, session),
            source: 'basic',
            authenticated: session['authenticated'] == true,
            metadata: {
              session_id: session.id&.private_id,
              expires_at: session['authenticated_at'] ? session['authenticated_at'] + 86_400 : nil,
              ip_address: session['ip_address'] || request.ip,
            },
          }
        rescue StandardError => ex
          logger.error "[IdentityResolution] Redis session error: #{ex.message}"
          no_identity
        end
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
        # Use existing Customer model to load by identity_id
        return nil unless session['identity_id']

        begin
          # Load Onetime::Customer if not already loaded
          #
          # TODO: This should be in lib/onetime if it's going to refer to
          # a Onetime model.
          require_relative '../onetime/models' unless defined?(Onetime::Customer)

          Onetime::Customer.load(session['identity_id'])
        rescue StandardError => ex
          logger.debug "[IdentityResolution] Could not load customer: #{ex.message}"
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

      def build_advanced_user(customer, session)
        # Build user object from Advanced-authenticated customer
        AdvancedUser.new(customer, session)
      end

      def build_basic_user(customer, session)
        # Return the customer object directly
        # Session metadata is already available in identity[:metadata]
        customer
      end

      def build_anonymous_user(request)
        # Return static, frozen anonymous customer
        Onetime::Customer.anonymous
      end

      def advanced_authenticated?(session)
        return false unless session['authenticated_at']
        return false unless session['account_external_id'] || session['advanced_account_id']

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
        if defined?(OT) && OT.respond_to?(:logger)
          OT.logger
        else
          Logger.new($stderr, level: Logger::INFO)
        end
      end
    end
  end
end

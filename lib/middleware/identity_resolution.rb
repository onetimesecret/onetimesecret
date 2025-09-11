# lib/middleware/identity_resolution.rb

module Rack
  # Identity Resolution Middleware for OneTimeSecret
  #
  # This middleware provides a flexible identity resolution layer that
  # bridges between the current Redis-based session system and future
  # authentication services (e.g., Rodauth with PostgreSQL/SQLite).
  #
  # The middleware resolves user identity from multiple sources in order
  # of precedence, allowing for gradual migration and mixed authentication
  # modes while maintaining backwards compatibility.
  #
  # ### Design Goals
  #
  # 1. **Backwards Compatibility**: Existing Redis sessions continue to work
  # 2. **Flexibility**: Support multiple identity sources simultaneously
  # 3. **Migration Path**: Enable gradual transition to new auth service
  # 4. **Zero Configuration**: Default to existing behavior for existing users
  # 5. **Enterprise Ready**: Support advanced authentication when configured
  #
  # ### Identity Resolution Order
  #
  # 1. **External Auth Service** - Check Rodauth-based service if configured
  # 2. **Redis Session** - Check existing session in Redis (current default)
  # 3. **Anonymous** - Fall back to anonymous user for public access
  #
  # ### Configuration
  #
  # ```ruby
  # # Enable external authentication service
  # OT.conf['site']['authentication']['external'] = {
  #   'enabled' => true,
  #   'service_url' => 'http://localhost:9393',
  #   'fallback_to_redis' => true
  # }
  # ```
  #
  # ### Usage
  #
  # ```ruby
  # use Rack::IdentityResolution
  # ```
  #
  # The middleware sets the following env variables:
  # - `env['identity.resolved']` - The resolved identity object
  # - `env['identity.source']` - Source of identity ('external', 'redis', 'anonymous')
  # - `env['identity.authenticated']` - Boolean authentication status
  #
  class IdentityResolution

    attr_reader :logger

    def initialize(app, logger: nil)
      @app = app
      @logger = logger || default_logger
    end

    def call(env)
      request = Rack::Request.new(env)

      # Resolve identity from available sources
      identity = resolve_identity(request, env)

      # Store resolved identity in environment
      env['identity.resolved'] = identity[:user]
      env['identity.source'] = identity[:source]
      env['identity.authenticated'] = identity[:authenticated]
      env['identity.metadata'] = identity[:metadata]

      logger.debug "[IdentityResolution] Resolved identity from #{identity[:source]}"

      @app.call(env)
    end

    private

    def resolve_identity(request, env)
      # Try external authentication service first if enabled
      if external_auth_enabled?
        external_identity = resolve_external_identity(request, env)
        return external_identity if external_identity[:user]
      end

      # Fall back to Redis session (current system)
      redis_identity = resolve_redis_identity(request, env)
      return redis_identity if redis_identity[:user]

      # Default to anonymous user
      resolve_anonymous_identity(request, env)
    end

    def resolve_external_identity(request, env)
      begin
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
              features: auth_response[:features] || []
            }
          }
        else
          logger.debug "[IdentityResolution] External auth validation failed"
          no_identity
        end

      rescue StandardError => e
        logger.error "[IdentityResolution] External auth error: #{e.message}"

        # Fallback to Redis if configured
        if external_auth_config['fallback_to_redis']
          logger.info "[IdentityResolution] Falling back to Redis session"
          no_identity # Let Redis resolver handle it
        else
          no_identity
        end
      end
    end

    def resolve_redis_identity(request, env)
      # Use existing session loading logic
      session_id = extract_session_id(request)
      return no_identity unless session_id

      begin
        # Load session from Redis (using existing OneTimeSecret logic)
        session = load_redis_session(session_id)
        return no_identity unless session

        {
          user: build_redis_user(session),
          source: 'redis',
          authenticated: session.authenticated?,
          metadata: {
            session_id: session_id,
            expires_at: session.expires_at,
            ip_address: request.ip
          }
        }

      rescue StandardError => e
        logger.error "[IdentityResolution] Redis session error: #{e.message}"
        no_identity
      end
    end

    def resolve_anonymous_identity(request, env)
      {
        user: build_anonymous_user(request),
        source: 'anonymous',
        authenticated: false,
        metadata: {
          ip_address: request.ip,
          user_agent: request.user_agent
        }
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

    def extract_session_id(request)
      request.cookies['sess']
    end

    def validate_with_external_service(token)
      # This would make an HTTP request to the Rodauth service
      # For now, return a placeholder structure

      service_url = external_auth_config['service_url']
      return nil unless service_url

      # TODO: Implement actual HTTP call to auth service
      # Example:
      # response = HTTP.post("#{service_url}/validate", json: { token: token })
      # JSON.parse(response.body)

      nil # Placeholder
    end

    def load_redis_session(session_id)
      # Use existing OneTimeSecret session loading logic
      # This would integrate with the current Session class

      return nil unless defined?(Session)

      begin
        Session.load(session_id)
      rescue StandardError => e
        logger.debug "[IdentityResolution] Could not load Redis session: #{e.message}"
        nil
      end
    end

    def build_external_user(user_data)
      # Build user object from external auth service data
      ExternalUser.new(user_data)
    end

    def build_redis_user(session)
      # Build user object from Redis session data
      RedisUser.new(session)
    end

    def build_anonymous_user(request)
      # Build anonymous user object
      AnonymousUser.new(
        ip_address: request.ip,
        user_agent: request.user_agent
      )
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
        metadata: {}
      }
    end

    def default_logger
      if defined?(OT) && OT.respond_to?(:logger)
        OT.logger
      else
        Logger.new($stderr, level: Logger::INFO)
      end
    end

    # User object implementations for different identity sources

    class ExternalUser
      attr_reader :id, :email, :roles, :features, :metadata

      def initialize(data)
        @id = data[:id] || data['id']
        @email = data[:email] || data['email']
        @roles = data[:roles] || data['roles'] || []
        @features = data[:features] || data['features'] || []
        @metadata = data[:metadata] || data['metadata'] || {}
      end

      def authenticated?
        true
      end

      def anonymous?
        false
      end

      def role?(role_name)
        roles.include?(role_name.to_s)
      end

      def feature_enabled?(feature_name)
        features.include?(feature_name.to_s)
      end
    end

    class RedisUser
      attr_reader :session

      def initialize(session)
        @session = session
      end

      def id
        session.custid
      end

      def email
        session.custid
      end

      def authenticated?
        session.authenticated?
      end

      def anonymous?
        !authenticated?
      end

      def role?(role_name)
        # Delegate to existing Customer logic if available
        return false unless session.respond_to?(:customer)
        return false unless session.customer

        session.customer.role?(role_name)
      end

      def feature_enabled?(feature_name)
        # Default Redis users have basic features
        %w[secrets create_secret view_secret].include?(feature_name.to_s)
      end

      def roles
        return [] unless authenticated?
        return [] unless session.respond_to?(:customer)
        return [] unless session.customer

        session.customer.roles || []
      end

      def features
        return [] unless authenticated?
        %w[secrets create_secret view_secret]
      end

      def metadata
        {
          session_created: session.created,
          last_access: session.accessed
        }
      end
    end

    class AnonymousUser
      attr_reader :ip_address, :user_agent

      def initialize(ip_address: nil, user_agent: nil)
        @ip_address = ip_address
        @user_agent = user_agent
      end

      def id
        nil
      end

      def email
        nil
      end

      def authenticated?
        false
      end

      def anonymous?
        true
      end

      def role?(role_name)
        false
      end

      def feature_enabled?(feature_name)
        # Anonymous users can view and create secrets by default
        %w[create_secret view_secret].include?(feature_name.to_s)
      end

      def roles
        []
      end

      def features
        %w[create_secret view_secret]
      end

      def metadata
        {
          ip_address: ip_address,
          user_agent: user_agent
        }
      end
    end
  end
end

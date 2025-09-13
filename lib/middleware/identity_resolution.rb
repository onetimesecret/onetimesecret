# lib/middleware/identity_resolution.rb

require 'logger'
require 'rack/request'

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
      # Check authentication mode (basic vs rodauth)
      auth_mode = detect_auth_mode

      case auth_mode
      when 'rodauth'
        # Try Rodauth session first
        rodauth_identity = resolve_rodauth_identity(request, env)
        return rodauth_identity if rodauth_identity[:user]
      when 'basic'
        # Use Redis-only authentication
        redis_identity = resolve_redis_identity(request, env)
        return redis_identity if redis_identity[:user]
      end

      # Default to anonymous user
      resolve_anonymous_identity(request, env)
    end

    def resolve_rodauth_identity(request, env)
      begin
        # Get session from Redis session middleware
        session = env['rack.session']
        return no_identity unless session

        # Check for Rodauth authentication markers
        return no_identity unless rodauth_authenticated?(session)

        # Load V2::Customer if not already loaded
        require_relative '../../apps/api/v2/models/customer' unless defined?(V2::Customer)

        # Lookup customer by derived extid
        customer = V2::Customer.find_by_extid(session['rodauth_external_id'])
        return no_identity unless customer

        {
          user: build_rodauth_user(customer, session),
          source: 'rodauth',
          authenticated: true,
          metadata: {
            customer_id: customer.objid,
            external_id: customer.extid,
            account_id: session['rodauth_account_id'],
            tenant_id: customer.primary_org_id,
            auth_method: 'rodauth',
            authenticated_at: session['authenticated_at'],
            expires_at: session['authenticated_at'] ? session['authenticated_at'] + 86400 : nil
          }
        }

      rescue StandardError => e
        logger.error "[IdentityResolution] Rodauth identity error: #{e.message}"
        no_identity
      end
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
      # Use Rack::Session from middleware
      session = env['onetime.session']
      return no_identity unless session && session['identity_id']

      begin
        # Load customer using identity_id from session
        customer = load_customer_from_session(session)
        return no_identity unless customer

        {
          user: build_redis_user(customer, session),
          source: 'redis',
          authenticated: session['authenticated'] == true,
          metadata: {
            session_id: session.id&.private_id,
            expires_at: session['authenticated_at'] ? session['authenticated_at'] + 86400 : nil,
            ip_address: session['ip_address'] || request.ip
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

    def load_customer_from_session(session)
      # Use existing Customer model to load by identity_id
      return nil unless session['identity_id']

      begin
        # Load V2::Customer if not already loaded
        require_relative '../../apps/api/v2/models/customer' unless defined?(V2::Customer)

        V2::Customer.load(session['identity_id'])
      rescue StandardError => e
        logger.debug "[IdentityResolution] Could not load customer: #{e.message}"
        nil
      end
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


    def build_external_user(user_data)
      # Build user object from external auth service data
      ExternalUser.new(user_data)
    end

    def build_rodauth_user(customer, session)
      # Build user object from Rodauth-authenticated customer
      RodauthUser.new(customer, session)
    end

    def build_redis_user(customer, session)
      # Build user object from customer and session data
      RedisUser.new(customer, session)
    end

    def build_anonymous_user(request)
      # Build anonymous user object
      AnonymousUser.new(
        ip_address: request.ip,
        user_agent: request.user_agent
      )
    end

    def rodauth_authenticated?(session)
      return false unless session['authenticated_at']
      return false unless session['rodauth_external_id'] || session['rodauth_account_id']

      # Check session age
      age = Time.now.to_i - session['authenticated_at']
      age < 86400  # 24 hours
    end

    def detect_auth_mode
      # Use auth configuration system if available
      if defined?(Onetime::AuthConfig)
        require_relative '../onetime/auth_config' unless defined?(Onetime::AuthConfig)
        return Onetime.auth_config.mode
      end

      # Fallback to environment variable
      mode = ENV['AUTHENTICATION_MODE']
      return mode if mode && %w[basic rodauth].include?(mode)

      # Final fallback: detect by database existence
      if File.exist?('data/auth.db')
        'rodauth'
      else
        'basic'
      end
    rescue
      'basic'  # Default to basic mode on any error
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

    class RodauthUser
      attr_reader :customer, :session

      def initialize(customer, session)
        @customer = customer
        @session = session
      end

      def id
        customer.objid
      end

      def email
        customer.custid
      end

      def authenticated?
        true  # Always authenticated if we reach this point
      end

      def anonymous?
        false
      end

      def role?(role_name)
        customer.role?(role_name) if customer.respond_to?(:role?)
      end

      def feature_enabled?(feature_name)
        # Rodauth users have full feature set
        %w[secrets create_secret view_secret admin].include?(feature_name.to_s)
      end

      def roles
        customer.roles || []
      end

      def features
        %w[secrets create_secret view_secret admin]
      end

      def metadata
        {
          customer_id: customer.objid,
          external_id: customer.extid,
          account_id: session['rodauth_account_id'],
          auth_method: 'rodauth',
          authenticated_at: session['authenticated_at'],
          expires_at: session['authenticated_at'] ? session['authenticated_at'] + 86400 : nil
        }
      end
    end

    class RedisUser
      attr_reader :customer, :session

      def initialize(customer, session)
        @customer = customer
        @session = session
      end

      def id
        customer.custid
      end

      def email
        customer.custid
      end

      def authenticated?
        session['authenticated'] == true && !customer.anonymous?
      end

      def anonymous?
        !authenticated?
      end

      def role?(role_name)
        customer.role?(role_name)
      end

      def feature_enabled?(feature_name)
        # Default Redis users have basic features
        %w[secrets create_secret view_secret].include?(feature_name.to_s)
      end

      def roles
        return [] unless authenticated?
        customer.roles || []
      end

      def features
        return [] unless authenticated?
        %w[secrets create_secret view_secret]
      end

      def metadata
        {
          session_created: session['authenticated_at'],
          last_access: session['last_seen'],
          ip_address: session['ip_address']
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

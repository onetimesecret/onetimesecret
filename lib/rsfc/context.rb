# lib/rsfc/context.rb

require_relative 'configuration'
require_relative 'adapters/base_auth'
require_relative 'adapters/base_session'

module RSFC
    # RSFCContext provides a clean interface for RSFC templates to access
    # server-side data. Follows the established pattern from InitScriptContext
    # and EnvironmentContext for focused, single-responsibility context objects.
    #
    # The context provides three layers of data:
    # 1. Runtime: Request metadata (CSRF tokens, nonces, request ID)
    # 2. Business: Application data (user, content, features)
    # 3. Computed: Server-side transformations and derived values
    #
    # One RSFCContext instance is created per page render and shared across
    # the main template and all partials to maintain security boundaries.
    class Context
      attr_reader :req, :sess, :cust, :locale, :runtime_data, :business_data, :computed_data, :config

      def initialize(req, sess = nil, cust = nil, locale_override = nil, business_data: {}, config: nil)
        @req           = req
        @sess          = sess || default_session
        @cust          = cust || default_customer
        @config        = config || RSFC.configuration
        @locale        = determine_locale(locale_override)
        @business_data = business_data.freeze

        # Build context layers
        @runtime_data  = build_runtime_data.freeze
        @computed_data = build_computed_data.freeze

        # Pre-compute all_data before freezing
        @all_data = @runtime_data.merge(@business_data).merge(@computed_data).freeze

        # Make context immutable after creation
        freeze
      end

      # Get variable value with dot notation support (e.g., "user.id", "features.account_creation")
      def get(variable_path)
        path_parts    = variable_path.split('.')
        current_value = all_data

        path_parts.each do |part|
          case current_value
          when Hash
            current_value = current_value[part] || current_value[part.to_sym]
          when Object
            if current_value.respond_to?(part)
              current_value = current_value.public_send(part)
            elsif current_value.respond_to?("#{part}?")
              current_value = current_value.public_send("#{part}?")
            else
              return nil
            end
          else
            return nil
          end

          return nil if current_value.nil?
        end

        current_value
      end

      # Get all available data (runtime + business + computed)
      attr_reader :all_data

      # Check if variable exists
      def has_variable?(variable_path)
        !get(variable_path).nil?
      end

      # Get list of all available variable paths (for validation)
      def available_variables
        collect_variable_paths(all_data)
      end

      # Resolve variable (alias for get method for hydrator compatibility)
      def resolve_variable(variable_path)
        get(variable_path)
      end

    private

      # Determine locale with priority order
      def determine_locale(locale_override)
        if locale_override
          locale_override
        elsif !req.nil? && req.env && req.env['ots.locale']
          req.env['ots.locale']
        else
          @config.default_locale
        end
      end

      # Build runtime data (request metadata)
      def build_runtime_data
        runtime = {}

        if req && req.respond_to?(:env) && req.env
          runtime['csrf_token']      = req.env.fetch(@config.csrf_token_name, nil)
          runtime['nonce']           = req.env.fetch(@config.nonce_header_name, nil)
          runtime['request_id']      = req.env.fetch('request_id', nil)
          runtime['domain_strategy'] = req.env.fetch('domain_strategy', :default)
          runtime['display_domain']  = req.env.fetch('display_domain', nil)
        end

        # Add basic app environment info
        runtime['app_environment'] = @config.app_environment
        runtime['api_base_url']    = @config.api_base_url

        runtime
      end

      # Build computed data (derived values)
      def build_computed_data
        computed = {}

        # Theme and UI state
        computed['theme_class']   = determine_theme_class
        computed['authenticated'] = authenticated?

        # Feature flags from configuration
        computed['features'] = @config.features

        # Development mode flags
        computed['development'] = @config.development?

        computed
      end

      # Build API base URL from configuration (deprecated - moved to config)
      def build_api_base_url
        @config.api_base_url
      end

      # Determine theme class for CSS
      def determine_theme_class
        # Default theme logic - can be overridden by business data
        if business_data['theme']
          "theme-#{business_data['theme']}"
        elsif cust && cust.respond_to?(:theme_preference)
          "theme-#{cust.theme_preference}"
        else
          'theme-light'
        end
      end

      # Check if user is authenticated
      def authenticated?
        sess && sess.authenticated? && cust && !cust.anonymous?
      end

      # Get default session instance
      def default_session
        RSFC::Adapters::AnonymousSession.new
      end

      # Get default customer instance
      def default_customer
        RSFC::Adapters::AnonymousAuth.new
      end

      # Recursively collect all variable paths from nested data
      def collect_variable_paths(data, prefix = '')
        paths = []

        case data
        when Hash
          data.each do |key, value|
            current_path = prefix.empty? ? key.to_s : "#{prefix}.#{key}"
            paths << current_path

            if value.is_a?(Hash) || value.is_a?(Object)
              paths.concat(collect_variable_paths(value, current_path))
            end
          end
        when Object
          # For objects, collect method names that look like attributes
          data.public_methods(false).each do |method|
            method_name = method.to_s
            next if method_name.end_with?('=') # Skip setters
            next if method_name.start_with?('_') # Skip private-ish methods

            current_path = prefix.empty? ? method_name : "#{prefix}.#{method_name}"
            paths << current_path
          end
        end

        paths
      end

      class << self
        # Create context with business data for a specific view
        def for_view(req, sess, cust, locale, config: nil, **business_data)
          new(req, sess, cust, locale, business_data: business_data, config: config)
        end

        # Create minimal context for testing
        def minimal(business_data: {}, config: nil)
          new(nil, nil, nil, 'en', business_data: business_data, config: config)
        end
      end
  end
end

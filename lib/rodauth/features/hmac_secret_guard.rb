# lib/rodauth/features/hmac_secret_guard.rb

module Rodauth
  # Automcatically sets hmac_secret based on HMAC_SECRET and validates it is are properly
  # configured before the application starts. This helps prevent deployment
  # errors where secret environment variables might not be set correctly,
  # particularly in production environments.
  #
  # By default, this feature checks during +post_configure+ that +hmac_secret+
  # is set to a non-nil, non-empty value. In production mode, it raises a
  # ConfigurationError if the secret is missing. In development mode, it logs
  # a warning and uses a fallback development secret.
  #
  # @example Basic Configuration
  #   plugin :rodauth do
  #     enable :secret_values_guard
  #   end
  #
  # @example Customizing Production Detection
  #   plugin :rodauth do
  #     enable :secret_values_guard
  #     production_env_check proc { ENV['RACK_ENV'] == 'production' }
  #     # Or use a boolean:
  #     # production_env_check true
  #   end
  #
  # @example Customizing Error Messages
  #   plugin :rodauth do
  #     enable :secret_values_guard
  #     hmac_secret_missing_error 'HMAC secret must be configured in production!'
  #     hmac_secret_dev_warning 'WARNING: Using insecure development HMAC secret'
  #   end
  #
  # @example Customizing Development Fallback
  #   plugin :rodauth do
  #     enable :secret_values_guard
  #     development_hmac_secret_fallback 'my-custom-dev-secret'
  #   end
  #
  # @example Disabling Validation
  #   plugin :rodauth do
  #     enable :secret_values_guard
  #     validate_secrets_on_configure? false
  #   end
  #
  Feature.define(:hmac_secret_guard, :HmacSecretGuard) do
    auth_value_method :hmac_secret_env_key, 'HMAC_SECRET'
    auth_value_method :production_env_check, proc { ENV.fetch('RACK_ENV', 'production') == 'production' }
    auth_value_method :validate_secrets_on_configure?, true
    auth_value_method :development_hmac_secret_fallback, 'dev-only-insecure-example-hmac-secret-needs-to-be-changed-in-prod'

    translatable_method :hmac_secret_missing_error, 'HMAC_SECRET environment variable must be set in production'
    translatable_method :hmac_secret_dev_warning, '[rodauth] WARNING: Using default HMAC secret for development only'

    def post_configure
      super

      # Auto-set hmac_secret if not already set
      if hmac_secret.nil? || (hmac_secret.respond_to?(:empty?) && hmac_secret.empty?)
        env_value = ENV.delete(hmac_secret_env_key)
        if env_value && !env_value.empty?
          self.class.send(:define_method, :hmac_secret) { env_value }
        end
      end

      # instance = klass.allocate.freeze
      # klass.define_singleton_method(:session_secret) { instance.hmac_secret }
      validate_secrets! if validate_secrets_on_configure?
    end

    auth_methods :validate_secrets!, :production?

    private

    # Check if we're running in production environment.
    #
    # @return [Boolean] true if running in production mode based on production_env_check
    def production?
      case v = production_env_check
      when Proc
        instance_exec(&v)
      else
        !!v
      end
    end

    # Validate that HMAC secret is properly configured.
    # Raises ConfigurationError in production if secret is missing.
    # In development, logs a warning and sets a fallback secret.
    #
    # @raise [Rodauth::ConfigurationError] if hmac_secret is missing in production
    # @return [void]
    def validate_secrets!
      # Get the current hmac_secret value (may be nil)
      current_secret = hmac_secret

      # Check if secret is missing or empty
      if current_secret.nil? || (current_secret.respond_to?(:empty?) && current_secret.empty?)
        if production?
          # In production, raise an error
          raise Rodauth::ConfigurationError, hmac_secret_missing_error
        else
          # In development, warn and set a fallback
          warn_dev_secret
          self.class.send(:define_method, :hmac_secret) { development_hmac_secret_fallback }
        end
      end
    end

    # Warn about using development secret.
    # Logs to logger if available, otherwise to stderr.
    #
    # @return [void]
    def warn_dev_secret
      if respond_to?(:logger) && logger
        logger.warn(hmac_secret_dev_warning)
      else
        $stderr.puts(hmac_secret_dev_warning)
      end
    end
  end
end

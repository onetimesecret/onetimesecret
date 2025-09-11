# app/services/auth/adapter_factory.rb

module Auth
  class AdapterFactory
    class << self
      def create(env)
        adapter_class = determine_adapter_class
        adapter_class.new(env)
      end

      def auth_mode
        # Check configuration for auth mode
        # Default to 'basic' if not configured
        config = OT.conf['site']['authentication'] || {}

        if config['external'] && config['external']['enabled']
          'rodauth'
        else
          'basic'
        end
      end

      def available_features
        # Return capabilities available in current auth mode
        # This can be queried by the frontend to enable/disable features
        case auth_mode
        when 'rodauth'
          {
            mode: 'rodauth',
            features: [
              'password_reset',
              'email_verification',
              'two_factor_auth',
              'oauth',
              'account_lockout',
              'password_complexity',
              'session_management',
              'audit_logging'
            ],
            external_service: true,
            fallback_enabled: fallback_to_redis?
          }
        else
          {
            mode: 'basic',
            features: [
              'password_reset',
              'session_management'
            ],
            external_service: false,
            fallback_enabled: false
          }
        end
      end

      private

      def determine_adapter_class
        case auth_mode
        when 'rodauth'
          require_relative 'rodauth_adapter'
          RodauthAdapter
        else
          require_relative 'basic_auth_adapter'
          BasicAuthAdapter
        end
      end

      def fallback_to_redis?
        config = OT.conf['site']['authentication'] || {}
        external = config['external'] || {}
        external['fallback_to_redis'] != false # Default true if not specified
      end
    end
  end
end

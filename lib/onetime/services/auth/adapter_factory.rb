# lib/onetime/services/auth/adapter_factory.rb

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
        config = OT.auth_config || {}
        config['mode']
      end

      private

      def determine_adapter_class
        case auth_mode
        when 'advanced'
          require_relative 'advanced_auth_adapter'
          AdvancedAuthAdapter
        when 'basic'
          require_relative 'basic_auth_adapter'
          BasicAuthAdapter
        else
          require_relative 'disabled_auth_adapter'
          DisabledAuthAdapter
        end
      end

    end
  end
end

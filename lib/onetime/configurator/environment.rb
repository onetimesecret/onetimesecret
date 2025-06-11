# lib/onetime/configurator/environment.rb

module Onetime
  class Configurator
    # Normalizes environment variables prior to loading and rendering the YAML
    # configuration. In some cases, this might include setting default values
    # and ensuring necessary environment variables are present.
    class EnvironmentContext
      def initialize(env = ENV.to_h)
        @env = normalize_env_vars(env.dup).freeze
      end

      def ENV = @env # rubocop:disable Naming/MethodName

      def get_binding = binding

      private

      # A wrapper that ensures whatever the normalizers do this will always
      # return the same hash object that was provided to us.
      def normalize_env_vars(env)
        normalize_regions_compatibility!(env)
        env
      end

      # In v0.20.6, REGIONS_ENABLE was renamed to REGIONS_ENABLED for
      # consistency. We ensure both are considered for compatability.
      def normalize_regions_compatibility!(env)
        set_value = env['REGIONS_ENABLED'] || env['REGIONS_ENABLE'] || 'false'
        env['REGIONS_ENABLED'] = set_value
      end

      class << self
        def template_binding = new.get_binding
      end
    end
  end
end

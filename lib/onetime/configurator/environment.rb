# lib/onetime/configurator/environment.rb

module Onetime
  class Configurator
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

      def normalize_regions_compatibility!(env)
        # Apply business logic here without touching global ENV
        set_value = env['REGIONS_ENABLED'] || env['REGIONS_ENABLE'] || 'false'
        env['REGIONS_ENABLED'] = set_value
      end

      class << self
        def template_binding = new.get_binding
      end
    end
  end
end

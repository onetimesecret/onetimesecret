# lib/onetime/services/service_registry.rb

require 'concurrent'

module Onetime
  module Services
    module ServiceRegistry
      @providers = Concurrent::Map.new
      @app_state = Concurrent::Map.new

      # TODO: Question, do the service providers follow the same pattarn of
      # each having a filename that corresponds to a top-level config section?
      # I think the answers is sometimes, depending on what kind of provider
      # it is. See the list of 3 types in this dir's README.md.

      class << self
        # Register a service provider
        def register(name, provider)
          @providers[name.to_sym] = provider
        end

        # Get a service provider by name
        def provider(name)
          @providers[name.to_sym]
        end

        # Set application state
        def set_state(key, value)
          @app_state[key.to_sym] = value
        end

        # Get application state
        def state(key)
          @app_state[key.to_sym]
        end

        # Hot reload capability
        def reload_all(new_config)
          @providers.each_value do |provider|
            provider.reload(new_config) if provider.respond_to?(:reload)
          end
        end

        # Check if all critical services are ready
        def ready?
          # Define critical services and check their status
          @providers.values.all? { |p| !p.respond_to?(:ready?) || p.ready? }
        end
      end
    end
  end
end

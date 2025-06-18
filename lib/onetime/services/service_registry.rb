# lib/onetime/services/service_registry.rb

require 'concurrent'

module Onetime
  module Services
    module ServiceRegistry

      # No accessors for safety. The only code directly accessing these
      # variables is within this module.
      @providers = Concurrent::Map.new
      @app_state = Concurrent::Map.new

      class << self
        # Register a service provider instance
        def register_provider(name, provider)
          @providers[name.to_s] = provider
        end

        # Get a service provider instance by name
        def provider(name)
          @providers[name.to_s]
        end

        # Set application state
        def set_state(key, value)
          @app_state[key.to_s] = value
        end

        # Typically we avoid getters and setters. These serve a helpful purpose
        # in normalizing the keys to strings. It avoids scenarios where we're
        # sure something should be working but the setting disappears only to
        # realize that we were using a symbol instead of a string. Knowing
        # get_state is available, it allows for a quick gut check. If we
        # find ourselves plopping calls to get_state too much, we can
        # trim them back to and or make adjustments to the design.
        def get_state(key)
          @app_state[key.to_s]
        end

        # Access application state hash (Concurrent::Map)
        #
        # e.g. Onetime::Services::ServiceRegistry.state['locales']
        #
        def state
          @app_state
        end

        def state_keys
          @app_state.keys
        end

        def provider_keys
          @providers.keys
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

# onetimesecret/lib/onetime/initializers/registry.rb
require 'tsort'

module Onetime
  module Initializers
    class Registry
      extend TSort
      @initializers = []
      @dependencies = {}

      class << self
        attr_reader :initializers, :dependencies

        # Register an initializer module with optional dependencies
        #
        # @param initializer_module [Module] The initializer module to register.
        #                                   It must respond to `self.run(options = {})`.
        # @param depends_on [Array<Module>] Initializers this one depends on.
        # @return [Array] The current list of registered initializers.
        def register(initializer_module, depends_on = [])
          unless initializer_module.respond_to?(:run)
            raise ArgumentError, "Initializer #{initializer_module} must respond to .run(options = {})"
          end
          initializers << initializer_module unless initializers.include?(initializer_module)
          dependencies[initializer_module] = Array(depends_on)
          OT.ld "[InitializerRegistry] Registered #{initializer_module} with dependencies: #{depends_on.inspect}"
        end

        # Run all registered initializers in dependency order.
        #
        # @param options [Hash] Options to pass to each initializer's `run` method.
        #                       Expected keys: `:mode`, `:connect_to_db`.
        def run_all!(options = {})
          OT.li "[InitializerRegistry] Running initializers..."
          sorted_initializers.each do |initializer_module|
            OT.ld "[InitializerRegistry] Running: #{initializer_module}"
            begin
              initializer_module.run(options)
              OT.ld "[InitializerRegistry] Finished: #{initializer_module}"
            rescue => e
              OT.le "[InitializerRegistry] Error running #{initializer_module}: #{e.message}"
              OT.ld e.backtrace.join("\n")
              raise "Failed to run initializer #{initializer_module}: #{e.message}"
            end
          end
          OT.li "[InitializerRegistry] All initializers run successfully."
        end

        # Get all serializers in dependency order
        #
        # @return [Array<Module>] Initializers sorted by dependency order
        def sorted_initializers
          tsort
        rescue TSort::Cyclic => e
          # Attempt to provide more detailed cycle information
          detailed_message = "Cyclic dependency detected in initializers. #{e.message}. Check dependencies: #{format_dependencies_for_cycle_error}"
          OT.le "[InitializerRegistry] #{detailed_message}"
          raise TSort::Cyclic, detailed_message # Re-raise with more info
        end

        # Get execution order information for display/debugging
        #
        # @return [Array<Hash>] Array of hashes with initializer info
        def execution_order
          sorted_initializers.map.with_index(1) do |initializer, index|
            deps = dependencies[initializer] || []
            {
              order: index,
              name: initializer.name,
              dependencies: deps.empty? ? [] : deps.map(&:name),
            }
          end
        rescue TSort::Cyclic => e
          # Return error info if there's a cycle
          [{
            order: 0,
            name: "ERROR",
            dependencies: ["Cyclic dependency detected: #{e.message}"],
          }]
        end

        # TSort interface implementation
        def tsort_each_node(&)
          initializers.each(&)
        end

        def tsort_each_child(node, &)
          dependencies.fetch(node, []).each(&)
        end

        private

        def format_dependencies_for_cycle_error
          # Basic formatting, could be enhanced to trace the cycle if TSort::Cyclic provided more info
          @dependencies.map do |mod, deps|
            "#{mod.name} depends on [#{deps.map(&:name).join(', ')}]"
          end.join('; ')
        end
      end
    end
  end
end

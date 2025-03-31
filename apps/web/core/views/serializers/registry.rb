# apps/web/core/views/serializers/registry.rb

require 'tsort'

# Dependencies-aware registry for view serializers
#
# The SerializerRegistry manages the registration, dependency resolution, and execution
# of serializers in the correct order. It uses Ruby's TSort module to handle dependency
# ordering.
#
# For this use case, module methods are preferable because:
#
# 1. Serializers perform a simple transformation without needing state
# 2. The data flow is linear and functional
# 3. Dependencies are handled by the registry, not individual serializers
# 4. The primary goal is to compose multiple independent transformations
#
# Usage examples:
#   SerializerRegistry.register(HTMLTags)
#   SerializerRegistry.register(JavaScriptVars, [HTMLTags]) # Depends on HTMLTags
#   SerializerRegistry.register(UserData, [JavaScriptVars]) # Depends on JavaScriptVars
#   SerializerRegistry.register(I18nData)
module Core
  module Views
    class SerializerRegistry
      extend TSort
      @serializers = []
      @dependencies = {}

      class << self
        attr_reader :serializers, :dependencies

        # Register a serializer with optional dependencies
        #
        # @param serializer [Module] The serializer to register
        # @param depends_on [Array<Module>] Serializers this one depends on
        # @return [Array] The current list of registered serializers
        def register(serializer, depends_on = [])
          serializers << serializer unless serializers.include?(serializer)
          dependencies[serializer] = Array(depends_on)
        end

        # Run specified serializers in dependency order
        #
        # @param serializer_list [Array<Module>] List of serializers to execute
        # @param vars [Hash] View variables to pass to each serializer
        # @param i18n [Object] Internationalization instance
        # @return [Hash] Combined output from all serializers
        def run(serializer_list, vars, i18n)
          # Get serializers in dependency order, filtering to requested ones
          ordered = sorted_serializers.select { |s| serializer_list.include?(s) }

          # Execute each serializer and merge results
          ordered.reduce({}) do |result, serializer|
            output = serializer.serialize(vars, i18n)
            if output.nil?
              OT.le "[SerializerRegistry] Warning: #{serializer} returned nil"
              next result
            end
            OT.ld "[SerializerRegistry] Executing serializer: #{serializer}"
            result.merge(output)
          end
        end

        # Get all serializers in dependency order
        #
        # @return [Array<Module>] Serializers sorted by dependency order
        def sorted_serializers
          tsort
        end

        # TSort interface implementation
        def tsort_each_node(&block)
          serializers.each(&block)
        end

        def tsort_each_child(node, &block)
          dependencies.fetch(node, []).each(&block)
        end
      end

    end
  end
end

# apps/web/core/views/serializers/registry.rb

require 'tsort'

#
# ComponentRegistry.register(self, [DomainManager])
#
# For this use case, module methods are preferable because:
#
# 1. Serializers perform a simple transformation without needing state
# 2. The data flow is linear and functional
# 3. Dependencies are handled by the registry, not individual serializers
# 4. The primary goal is to compose multiple independent transformations
#
# If your serializers need complex configuration, internal state, or inheritance relationships, a class-based approach would be more appropriate.
#
# Register serializers with their dependencies
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

        def register(serializer, depends_on = [])
          serializers << serializer unless serializers.include?(serializer)
          dependencies[serializer] = Array(depends_on)
        end

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

        # Simple flat merge of component serializers
        def reconcile(serializers)
          serializers.reduce({}) do |result, export_data|
            result.merge(export_data)
          end
        end
      end

    end
  end
end

# Alternate suggested implementation. Not sure it needs to be so complicated.
#
# module Core
#   module Views
#     class SerializerRegistry
#       extend TSort
#       @serializers = {}
#       @dependencies = {}

#       class << self
#         attr_reader :serializers, :dependencies

#         # Register a serializer with its dependencies
#         def register(serializer, depends_on = [])
#           serializers[serializer] = true
#           dependencies[serializer] = Array(depends_on)
#         end

#         # Execute serializers in dependency order
#         def run(serializer_list, vars, i18n)
#           # Get ordered list respecting dependencies
#           ordered = sort_serializers(serializer_list)

#           # Run each serializer and merge results
#           result = {}
#           ordered.each do |serializer|
#             data = serializer.serialize(vars, i18n)
#             result.merge!(data)
#           end

#           result
#         end

#         private

#         # Sort a list of serializers respecting dependencies
#         def sort_serializers(serializer_list)
#           # Create a subgraph with just the requested serializers
#           temp_deps = {}

#           serializer_list.each do |s|
#             deps = dependencies[s] || []
#             # Only include dependencies that are in our requested list
#             included_deps = deps.select { |d| serializer_list.include?(d) }
#             temp_deps[s] = included_deps
#           end

#           # Sort the subgraph
#           sort_with_deps(serializer_list, temp_deps)
#         end

#         # Simple topological sort implementation
#         def sort_with_deps(nodes, deps)
#           result = []
#           visited = {}

#           # Visit each node
#           nodes.each do |node|
#             visit(node, deps, visited, result) unless visited[node]
#           end

#           result
#         end

#         def visit(node, deps, visited, result)
#           visited[node] = true

#           # Visit all dependencies first
#           (deps[node] || []).each do |dep|
#             visit(dep, deps, visited, result) unless visited[dep]
#           end

#           # Then add this node
#           result << node
#         end
#       end
#     end
#   end
# end

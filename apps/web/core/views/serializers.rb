# apps/web/core/views/serializer_registry.rb

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

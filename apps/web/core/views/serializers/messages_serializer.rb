# apps/web/core/views/serializers/messages_serializer.rb

module Core
  module Views
    module MessagesSerializer
      # Rack Request object
      def self.serialize(view_vars, i18n)
        output = self.output_template

        output[:messages] = view_vars[:messages]
        output[:global_banner] = OT.global_banner if OT.global_banner

        output
      end

      private

      def self.output_template
        {
          messages: [],
          global_banner: nil,
        }
      end

      SerializerRegistry.register(self)
    end
  end
end

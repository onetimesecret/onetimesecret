# apps/web/core/views/serializers/messages_serializer.rb

module Core
  module Views
    module MessagesSerializer
      # Rack Request object
      def self.serialize(view_vars, i18n)
        output = self.output_template

        output[:messages] = self[:messages]
        output[:global_banner] = OT.global_banner if OT.global_banner
      end

      private

      def self.output_template
        {
          messages: [],
          global_banner: nil,
        }
      end

    end
  end
end

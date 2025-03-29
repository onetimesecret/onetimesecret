# apps/web/core/views/serializers/messages_serializer.rb

module Core
  module Views
    module MessagesSerializer
      # Rack Request object
      def self.serialize(view_vars, i18n)
        self[:jsvars][:messages] = jsvar(self[:messages])
        self[:jsvars][:global_banner] = jsvar(OT.global_banner) if OT.global_banner
      end

      private

      def self.output_template
        {}
      end

    end
  end
end

# apps/web/core/views/serializers/messages_serializer.rb

module Core
  module Views

    # Serializes flash messages and global notifications for the frontend
    #
    # Responsible for transforming user-facing messages, notifications,
    # and global banners for frontend display.
    module MessagesSerializer

      # Serializes messages data from view variables
      #
      # @param view_vars [Hash] The view variables containing message information
      # @param i18n [Object] The internationalization instance
      # @return [Hash] Serialized messages and global banner information
      def self.serialize(view_vars, i18n)
        output = self.output_template

        output[:messages] = view_vars[:messages]
        output[:global_banner] = OT.global_banner if OT.global_banner

        output
      end

      class << self
        private

        # Provides the base template for messages serializer output
        #
        # @return [Hash] Template with all possible message output fields
        def output_template
          {
            messages: [],
            global_banner: nil,
          }
        end
      end

      SerializerRegistry.register(self)
    end
  end
end

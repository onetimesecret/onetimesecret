# apps/web/core/views/serializers/request_serializer.rb

module Core
  module Views
    module RequestSerializer
      # Rack Request object
      def self.serialize(view_vars, i18n)
        # Add the nonce to the jsvars hash if it exists. See `carefully`.
        self[:nonce] = req.env.fetch('ots.nonce', nil)
      end

      private

      def self.output_template
        {}
      end

    end
  end
end

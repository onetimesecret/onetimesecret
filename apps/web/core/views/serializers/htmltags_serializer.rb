# apps/web/core/views/serializers/htmltags_serializer.rb

module Core
  module Views
    module HTMLTagsSerializer
      # :description, :keywords, :page_title, :no_cache
      # :frontend_host, :frontend_development, :nonce
      def self.serialize(view_vars, i18n)
        output = self.output_template

        # Regular template vars used by head.html
        output[:description] = i18n[:COMMON][:description]
        output[:keywords] = i18n[:COMMON][:keywords]
        output[:page_title] = "Onetime Secret" # TODO: Implement as config setting
        output[:no_cache] = false
        output[:frontend_host] = view_vars[:frontend_host]
        output[:frontend_development] = view_vars[:frontend_development]
        output[:nonce] = view_vars[:nonce]

        p [:PLOPPLOP, self, output.class]

        output
      end

      private

      def self.output_template
        {
          description: nil,
          keywords: nil,
          page_title: nil,
          no_cache: nil,
          frontend_host: nil,
          frontend_development: nil,
          nonce: nil,
        }
      end

      SerializerRegistry.register(self)
    end
  end
end

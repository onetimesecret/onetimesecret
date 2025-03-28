# apps/web/core/views/serializers/htmltags_serializer.rb

module Core
  module Views
    module HTMLTags
      def self.serialize(vars, i18n)
        output = self.output_template

        # Regular template vars used by head.html
        output[:description] = i18n[:COMMON][:description]
        output[:keywords] = i18n[:COMMON][:keywords]
        output[:page_title] = "Onetime Secret"
        output[:no_cache] = false
        output[:frontend_host] = @frontend_host
        output[:frontend_development] = @frontend_development
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
        }
      end
    end
  end
end

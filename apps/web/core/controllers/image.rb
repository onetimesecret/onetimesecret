# apps/web/core/controllers/image.rb

require_relative 'base'

module Core
  module Controllers
    class Image
      include Controllers::Base

      # /imagine/b79b17281be7264f778c/logo.png
      def imagine
        logic = V2::Logic::Domains::GetImage.new request, session, cust, req.params
        logic.raise_concerns
        logic.process

        res['content-type'] = logic.content_type

        # Return the response with appropriate headers
        res['Content-Length'] = logic.content_length
        res.write(logic.image_data)

        res.finish
      end
    end
  end
end

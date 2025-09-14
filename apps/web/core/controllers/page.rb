require_relative 'base'

module Core
  module Controllers
    class Page
      include Controllers::Base

      def index
        publically do
          view     = Core::Views::VuePoint.new request, session, cust, locale
          res.body = view.render
        end
      end

      # /imagine/b79b17281be7264f778c/logo.png
      def imagine
        publically(false) do
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

      def customers_only
        authenticated do
          view     = Core::Views::VuePoint.new request, session, cust, locale
          res.body = view.render
        end
      end

      def colonels_only
        colonels do
          view     = Core::Views::VuePoint.new request, session, cust, locale
          res.body = view.render
        end
      end

      def robots_txt
        publically do
          view                       = Core::Views::RobotsTxt.new request, session, cust, locale
          res.headers['content-type'] = 'text/plain'
          res.body                   = view.render
        end
      end
    end
  end
end

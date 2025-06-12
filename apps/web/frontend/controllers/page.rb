
require_relative 'base'

module Frontend
  module Controllers
    class Page
      include Controllers::Base

      # /imagine/b79b17281be7264f778c/logo.png
      def imagine
        publically(false) do
          logic = V2::Logic::Domains::GetImage.new sess, cust, req.params
          logic.raise_concerns
          logic.process

          res['Content-Type'] = logic.content_type

          # Return the response with appropriate headers
          res['Content-Length'] = logic.content_length
          res.write(logic.image_data)

          res.finish
        end
      end

      def index
        publically do
          OT.ld "[index] authenticated? #{sess.authenticated?}"
          view = Frontend::Views::VuePoint.new req, sess, cust, locale
          sess.event_incr! :get_page
          res.body = view.render
        end
      end

      def customers_only
        authenticated do
          OT.ld "[customers_only] authenticated? #{sess.authenticated?}"
          view = Frontend::Views::VuePoint.new req, sess, cust, locale
          sess.event_incr! :get_page
          res.body = view.render
        end
      end

      def colonels_only
        colonels do
          OT.ld "[colonels_only] authenticated? #{sess.authenticated?}"
          view = Frontend::Views::VuePoint.new req, sess, cust, locale
          sess.event_incr! :get_page
          res.body = view.render
        end
      end

      def robots_txt
        publically do
          view = Frontend::Views::RobotsTxt.new req, sess, cust, locale
          sess.event_incr! :robots_txt
          res.header['Content-Type'] = 'text/plain'
          res.body = view.render
        end
      end
    end
  end
end

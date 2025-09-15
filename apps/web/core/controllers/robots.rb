# apps/web/core/controllers/robots.rb

require_relative 'base'

module Core
  module Controllers
    class Robots
      include Controllers::Base

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

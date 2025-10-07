# apps/web/core/controllers/page.rb

require_relative 'base'

module Core
  module Controllers
    class Page
      include Controllers::Base

      # /imagine/b79b17281be7264f778c/logo.png
      def imagine
        logic = V2::Logic::Domains::GetImage.new req, session, cust, req.params
        logic.raise_concerns
        logic.process

        res['content-type'] = logic.content_type

        # Return the response with appropriate headers
        res['Content-Length'] = logic.content_length
        res.write(logic.image_data)

        res.finish
      end

      def export_window
        OT.ld "[export_window] authenticated? #{authenticated?}"
        view                       = Core::Views::ExportWindow.new req, session, cust, locale
        res.headers['content-type'] = 'application/json; charset=utf-8'
        res.body                   = view.serialized_data.to_json
      end

      def robots_txt
        view                       = Core::Views::RobotsTxt.new request, session, cust, locale
        res.headers['content-type'] = 'text/plain'
        res.body                   = view.render
      end


    end
  end
end

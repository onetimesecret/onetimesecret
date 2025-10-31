# apps/web/core/controllers/page.rb

require_relative 'base'

module Core
  module Controllers
    class Page
      include Controllers::Base

      # /imagine/b79b17281be7264f778c/logo.png
      def imagine
        logic = V2::Logic::Domains::GetImage.new(req, session, cust, req.params)
        logic.raise_concerns
        logic.process

        res['content-type']   = logic.content_type
        res['content-length'] = logic.content_length
        res.write(logic.image_data)
        res.finish
      end

      def export_window
        rack_session = req.env['rack.session']
        session_logger.debug "Exporting window state", {
          session_class: rack_session.class.name,
          session_id: (rack_session.id.public_id rescue 'no-id'),
          session_keys: (rack_session.keys rescue []),
          authenticated: rack_session['authenticated'],
          has_external_id: !rack_session['external_id'].nil?,
          authenticated_check: authenticated?
        }
        view = Core::Views::ExportWindow.new(req, session, cust, locale)
        res.headers['content-type'] = 'application/json; charset=utf-8'
        res.body = view.serialized_data.to_json
      end

      def robots_txt
        view = Core::Views::RobotsTxt.new(request, session, cust, locale)
        res.headers['content-type'] = 'text/plain'
        res.body                    = view.render
      end
    end
  end
end

# apps/web/core/controllers/data.rb

require_relative 'base'

module Core
  module Controllers
    class Data
      include Controllers::Base

      def export_window
        publically do
          OT.ld "[export_window] authenticated? #{sess.authenticated?}"
          view                       = Core::Views::ExportWindow.new req, sess, cust, locale
          res.header['Content-Type'] = 'application/json; charset=utf-8'
          res.body                   = view.serialized_data.to_json
        end
      end

      def create_incoming
        publically(req.request_path) do
          if OT.conf['incoming'] && OT.conf['incoming']['enabled']
            logic    = V2::Logic::Incoming::CreateIncoming.new sess, cust, req.params, locale
            logic.raise_concerns
            logic.process
            req.params.clear
            view     = Core::Views::Incoming.new req, sess, cust, locale
            view.add_message view.i18n[:page][:incoming_success_message]
            res.body = view.render
          else
            res.redirect '/'
          end
        end
      end
    end
  end
end

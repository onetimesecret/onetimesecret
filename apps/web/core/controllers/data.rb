# apps/web/core/controllers/data.rb

require_relative 'base'

module Core
  module Controllers
    class Data
      include Controllers::Base

      def export_window
        publically do
          OT.ld "[export_window] authenticated? #{sess.authenticated?}"
          view = Core::Views::ExportWindow.new req, sess, cust, locale
          sess.event_incr! :get_page
          res.header['Content-Type'] = "application/json; charset=utf-8"
          res.body = view.serialized_data.to_json
        end
      end
    end
  end

end

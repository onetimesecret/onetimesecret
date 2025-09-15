# apps/web/core/controllers/data_export.rb

require_relative 'base'

module Core
  module Controllers
    class DataExport
      include Controllers::Base

      def export_window
        publically do
          OT.ld "[export_window] authenticated? #{session.authenticated?}"
          view                       = Core::Views::ExportWindow.new req, session, cust, locale
          res.headers['content-type'] = 'application/json; charset=utf-8'
          res.body                   = view.serialized_data.to_json
        end
      end
    end
  end
end

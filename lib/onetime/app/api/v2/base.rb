require_relative '../../helpers'


class Onetime::App
  class APIV2
    module Base
      include Onetime::App::Helpers


      def json hsh
        res.header['Content-Type'] = "application/json; charset=utf-8"
        res.body = hsh.to_json
      end

      def handle_form_error ex, redirect
        error_response ex.message
      end

      def not_found_response msg, hsh={}
        hsh[:message] = msg
        res.status = 404
        json hsh
      end

      def error_response msg, hsh={}
        hsh[:message] = msg
        res.status = 500
        json hsh
      end

    end
  end
end

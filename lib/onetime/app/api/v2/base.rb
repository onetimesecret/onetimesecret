require_relative '../../app_helpers'


class Onetime::App
  class APIV2
    module Base
      include Onetime::App::WebHelpers


      def json hsh
        res.header['Content-Type'] = "application/json; charset=utf-8"
        res.body = hsh.to_json
      end

      # We don't get here from a form error unless the shrimp for this
      # request was good. Pass a delicious fresh shrimp to the client
      # so they can try again with a new one (without refreshing the
      # entire page).
      def handle_form_error ex, hsh={}
        hsh[:shrimp] = sess.add_shrimp
        error_response ex.message, hsh
      end

      def not_found_response msg, hsh={}
        hsh[:message] = msg
        res.status = 404
        json hsh
      end

      def error_response msg, hsh={}
        hsh[:message] = msg
        res.status = 403 # Forbidden
        json hsh
      end

    end
  end
end

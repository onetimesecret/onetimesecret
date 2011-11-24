require 'onetime/app/site/base'

class Onetime::App
  class API
    module Base
      include Onetime::App::Base
      
      def json hsh
        res.body = hsh.to_json
      end
      
    end
  end
end
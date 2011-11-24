
require 'onetime/app/api/base'

class Onetime::App
  class API
    include Onetime::App::API::Base
  
    def status
      anonymous do
        sess.event_incr! :homepage
        json :status => :nominal
      end
    end

  end
end

require 'onetime/app/api/base'

class Onetime::App
  class API
    include Onetime::App::API::Base
      
    def status
      anonymous do
        sess.event_incr! :check_status
        json :status => :nominal
      end
    end

    def share
      anonymous do
        req.params[:kind] = :share
        logic = OT::Logic::CreateSecret.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        res.redirect app_path(logic.redirect_uri)
      end
    end

    def generate
      anonymous do
        req.params[:kind] = :generate
        logic = OT::Logic::CreateSecret.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        res.redirect app_path(logic.redirect_uri)
      end
    end
    
    def show_secret
      anonymous do
        req.params[:continue] = 'true'
        logic = OT::Logic::ShowSecret.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        p logic.secret.all
        if logic.show_secret
          json :secret => logic.secret_value
          logic.secret.destroy!
        else
          not_found :msg => 'Unknown secret'
        end
      end
    end
    
    def show_metadata
      anonymous do
        logic = OT::Logic::ShowMetadata.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        if logic.show_secret
          json logic.metadata.all
          logic.metadata.delete :secret_key
        else
          json logic.metadata.all
        end
      end
    end
    
  end
end
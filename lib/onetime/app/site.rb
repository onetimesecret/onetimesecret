
require 'onetime'  # must be required before
require 'onetime/app/site/base'
require 'onetime/app/site/views'

module Onetime
  class App
    include Base
  
    def index
      anonymous do
        view = Onetime::Views::Homepage.new req
        sess.event_incr! :homepage
        res.body = view.render
      end
    end
  
    #def not_found
    #  [404, {'Content-Type'=>'text/plain'}, ["Server error2"]]
    #end
  
    def create
      anonymous do
        logic = OT::Logic::CreateSecret.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        res.redirect logic.redirect_uri
      end
    end
  
    def secret_uri
      anonymous do
        deny_agents! 
        logic = OT::Logic::ShowSecret.new sess, cust, req.params
        view = Onetime::Views::Shared.new req, res
        logic.raise_concerns
        logic.process
        view[:has_passphrase] = logic.secret.has_passphrase?
        if logic.show_secret
          view[:show_secret] = true
          view[:secret_value] = logic.secret_value
        elsif req.post?
          view[:err] = "Double check that passphrase"
        end
        res.body = view.render
      end
    end
 
    def private_uri
      carefully do
        deny_agents! 
        logic = OT::Logic::ShowMetadata.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        view = Onetime::Views::Private.new req, res, logic.metadata, logic.secret
        if logic.show_secret
          view[:show_secret] = true
        end
        res.body = view.render
      end
    end
  
    class Info
      include Base
      def privacy
        carefully do
          view = Onetime::Views::Info::Privacy.new req
          res.body = view.render
        end
      end
      def security
        carefully do
          view = Onetime::Views::Info::Security.new req
          res.body = view.render
        end
      end
    end
  end
end


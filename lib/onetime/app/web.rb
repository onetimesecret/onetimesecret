
require 'onetime'  # must be required before
require 'onetime/app/web/base'
require 'onetime/app/web/views'

module Onetime
  class App
    include Base
    
    def index
      anonymous do
        view = Onetime::Views::Homepage.new req, sess, cust
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
        res.redirect app_path(logic.redirect_uri)
      end
    end
  
    def secret_uri
      anonymous do
        deny_agents! 
        logic = OT::Logic::ShowSecret.new sess, cust, req.params
        view = Onetime::Views::Shared.new req, sess, cust
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
      anonymous do
        deny_agents! 
        logic = OT::Logic::ShowMetadata.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        view = Onetime::Views::Private.new req, sess, cust, logic.metadata, logic.secret
        if logic.show_secret
          view[:show_secret] = true
        end
        res.body = view.render
      end
    end
    
    def pricing
      anonymous do
        view = Onetime::Views::Pricing.new req, sess, cust
        res.body = view.render
      end
    end
    
    def signup
      anonymous do
        view = Onetime::Views::Signup.new req, sess, cust
        res.body = view.render
      end
    end
    
    def create_account
      anonymous do
        deny_agents! 
        logic = OT::Logic::CreateAccount.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        res.redirect '/dashboard'
      end
    end
    
    def login
      anonymous do
        view = Onetime::Views::Login.new req, sess, cust
        res.body = view.render
      end
    end
    
    def authenticate
      anonymous do
        res.redirect '/dashboard'
      end
    end
    
    def dashboard
      anonymous do
        logic = OT::Logic::Dashboard.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        view = Onetime::Views::Dashboard.new req, sess, cust
        res.body = view.render
      end
    end
    
    class Info
      include Base
      def privacy
        anonymous do
          view = Onetime::Views::Info::Privacy.new req, sess, cust
          res.body = view.render
        end
      end
      def security
        anonymous do
          view = Onetime::Views::Info::Security.new req, sess, cust
          res.body = view.render
        end
      end
    end
  end
end


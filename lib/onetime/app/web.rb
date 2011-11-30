
require 'onetime'  # must be required before
require 'onetime/app/web/base'
require 'onetime/app/web/views'

module Onetime
  class App
    include Base
    
    def index
      carefully do
        view = Onetime::Views::Homepage.new req, sess, cust
        sess.event_incr! :homepage
        res.body = view.render
      end
    end
  
    #def not_found
    #  [404, {'Content-Type'=>'text/plain'}, ["Server error2"]]
    #end
  
    def create_secret
      carefully(req.request_path) do
        logic = OT::Logic::CreateSecret.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        res.redirect app_path(logic.redirect_uri)
      end
    end
  
    def secret_uri
      carefully do
        deny_agents! 
        logic = OT::Logic::ShowSecret.new sess, cust, req.params
        view = Onetime::Views::Shared.new req, sess, cust
        logic.raise_concerns
        logic.process
        view[:has_passphrase] = logic.secret.has_passphrase?
        view[:verification] = logic.verification
        if logic.show_secret
          view[:show_secret] = true
          view[:secret_value] = logic.secret_value
          view[:original_size] = logic.original_size
          view[:truncated] = logic.truncated
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
        view = Onetime::Views::Private.new req, sess, cust, logic.metadata
        view[:show_secret] = true if logic.show_secret
        res.body = view.render
      end
    end
    
    def pricing
      carefully do
        view = Onetime::Views::Pricing.new req, sess, cust
        res.body = view.render
      end
    end
    
    def signup
      carefully do
        if OT::Plan.plan?(req.params[:planid])
          sess.set_error_message "You're already signed up" if sess.authenticated?
          view = Onetime::Views::Signup.new req, sess, cust
          res.body = view.render
        else
          res.redirect app_path('/')
        end
      end
    end
    
    def create_account
      carefully("/signup/#{req.params[:planid]}") do
        deny_agents! 
        logic = OT::Logic::CreateAccount.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        sess, cust = logic.sess, logic.cust
        res.redirect '/dashboard'
      end
    end
    
    def login
      carefully do
        view = Onetime::Views::Login.new req, sess, cust
        res.body = view.render
      end
    end
    
    def authenticate
      carefully do
        logic = OT::Logic::AuthenticateSession.new sess, cust, req.params
        view = Onetime::Views::Login.new req, sess, cust
        if sess.authenticated?
          sess.msg! "You are already logged in."
          res.redirect '/'
        else
          if req.post?
            logic.raise_concerns
            logic.process
            sess, cust = logic.sess, logic.cust
            res.send_cookie :sess, sess.sessid, sess.ttl
            res.redirect '/dashboard'
          else
            view.cust = OT::Customer.anonymous
            res.body = view.render
          end
        end
      end
    end
    
    def logout
      authenticated do
        logic = OT::Logic::DestroySession.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        res.redirect app_path('/')
      end
    end
    
    def dashboard
      authenticated do
        logic = OT::Logic::Dashboard.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        view = Onetime::Views::Dashboard.new req, sess, cust
        res.body = view.render
      end
    end
    
    def account
      authenticated do
        logic = OT::Logic::ViewAccount.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        view = Onetime::Views::Account.new req, sess, cust
        res.body = view.render
      end
    end

    def update_account
      authenticated do
        logic = OT::Logic::UpdateAccount.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        res.redirect app_path('/account')
      end
    end
    
    class Info
      include Base
      def privacy
        carefully do
          view = Onetime::Views::Info::Privacy.new req, sess, cust
          res.body = view.render
        end
      end
      def security
        carefully do
          view = Onetime::Views::Info::Security.new req, sess, cust
          res.body = view.render
        end
      end
    end
  end
end



require 'onetime'  # must be required before
require 'onetime/app/web/base'
require 'onetime/app/web/views'

module Onetime
  class App
    include Base
    require 'onetime/app/web/info'
    require 'onetime/app/web/account'
    
    #def not_found
    #  [404, {'Content-Type'=>'text/plain'}, ["Server error2"]]
    #end
    
    def index
      publically do
        view = Onetime::App::Views::Homepage.new req, sess, cust
        sess.event_incr! :homepage
        res.body = view.render
      end
    end
    
    def show_docs
      authenticated do
        if plan.options[:api]
          view = Onetime::App::Views::Docs::Api.new req, sess, cust
          res.body = view.render
        else
          res.redirect app_path('/')
        end
      end
    end
    
    def receive_feedback
      publically do
        logic = OT::Logic::ReceiveFeedback.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        res.redirect app_path('/feedback')
      end
    end
    
    def dashboard
      authenticated do
        logic = OT::Logic::Dashboard.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        view = Onetime::App::Views::Dashboard.new req, sess, cust
        res.body = view.render
      end
    end
    
    def create_secret
      publically(req.request_path) do
        logic = OT::Logic::CreateSecret.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        res.redirect app_path(logic.redirect_uri)
      end
    end
    
    def secret_uri
      publically do
        deny_agents! 
        logic = OT::Logic::ShowSecret.new sess, cust, req.params
        view = Onetime::App::Views::Shared.new req, sess, cust
        logic.raise_concerns
        logic.process
        view[:has_passphrase] = logic.secret.has_passphrase?
        view[:verification] = logic.verification
        if logic.show_secret
          view[:show_secret] = true
          view[:secret_value] = logic.secret_value
          view[:original_size] = logic.original_size
          view[:truncated] = logic.truncated
        elsif req.post? && !logic.correct_passphrase
          view.add_error   "Double check that passphrase"
        end
        res.body = view.render
      end
    end
    
    def private_uri
      publically do
        deny_agents!
        logic = OT::Logic::ShowMetadata.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        view = Onetime::App::Views::Private.new req, sess, cust, logic.metadata
        view[:show_secret] = true if logic.show_secret
        res.body = view.render
      end
    end
    
    def passgen
      publically do
        view = Onetime::App::Views::PasswordGenerator.new req, sess, cust
        res.body = view.render
      end
    end
    def about
      publically do
        view = Onetime::App::Views::About.new req, sess, cust
        res.body = view.render
      end
    end
    def logo 
      publically do
        view = Onetime::App::Views::Logo.new req, sess, cust
        res.body = view.render
      end
    end
    def feedback
      publically do
        view = Onetime::App::Views::Feedback.new req, sess, cust
        res.body = view.render
      end
    end
  end
end


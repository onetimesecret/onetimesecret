
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
      carefully do
        view = Onetime::App::Views::Homepage.new req, sess, cust
        sess.event_incr! :homepage
        res.body = view.render
      end
    end
    
    def receive_feedback
      carefully do
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
      carefully do
        deny_agents!
        logic = OT::Logic::ShowMetadata.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        view = Onetime::App::Views::Private.new req, sess, cust, logic.metadata
        view[:show_secret] = true if logic.show_secret
        res.body = view.render
      end
    end
    
    def bookmarklet
      carefully do
        view = Onetime::App::Views::Bookmarklet.new req, sess, cust
        res.body = view.render
      end
    end
    def about
      carefully do
        view = Onetime::App::Views::About.new req, sess, cust
        res.body = view.render
      end
    end
    def feedback
      carefully do
        view = Onetime::App::Views::Feedback.new req, sess, cust
        res.body = view.render
      end
    end
  end
end


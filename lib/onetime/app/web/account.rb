module Onetime
  class App
    
    def login
      carefully do
        view = Onetime::App::Views::Login.new req, sess, cust
        res.body = view.render
      end
    end
    
    def pricing
      carefully do
        view = Onetime::App::Views::Pricing.new req, sess, cust
        res.body = view.render
      end
    end
    
    def signup
      carefully do
        if OT::Plan.plan?(req.params[:planid])
          sess.set_error_message "You're already signed up" if sess.authenticated?
          view = Onetime::App::Views::Signup.new req, sess, cust
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
    
    def authenticate
      carefully do
        logic = OT::Logic::AuthenticateSession.new sess, cust, req.params
        view = Onetime::App::Views::Login.new req, sess, cust
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
    
    def account
      authenticated do
        logic = OT::Logic::ViewAccount.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        view = Onetime::App::Views::Account.new req, sess, cust
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
  end
end
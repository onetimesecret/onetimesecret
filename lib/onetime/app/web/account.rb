module Onetime
  class App
    
    def forgot
      publically do
        if req.params[:key]
          secret = OT::Secret.load req.params[:key]
          if secret.nil? || secret.verification.to_s != 'true'
            raise OT::MissingSecret if secret.nil?
          else
            view = Onetime::App::Views::Forgot.new req, sess, cust
            view[:verified] = true
            res.body = view.render
          end
        else
          view = Onetime::App::Views::Forgot.new req, sess, cust
          res.body = view.render
        end
      end
    end
    
    def request_reset
      publically do
        if req.params[:key]
          logic = OT::Logic::ResetPassword.new sess, cust, req.params
          logic.raise_concerns
          logic.process
          res.redirect '/login'
        else
          logic = OT::Logic::ResetPasswordRequest.new sess, cust, req.params
          logic.raise_concerns
          logic.process
          res.redirect '/'
        end
      end
    end
    
    def login
      publically do
        view = Onetime::App::Views::Login.new req, sess, cust
        res.body = view.render
      end
    end
    
    def pricing
      res.redirect '/signup'
    end
    
    def signup
      publically do
        if OT::Plan.plan?(req.params[:planid])
          sess.set_error_message "You're already signed up" if sess.authenticated?
          view = Onetime::App::Views::Signup.new req, sess, cust
          res.body = view.render
        else
          view = Onetime::App::Views::Pricing.new req, sess, cust
          res.body = view.render
        end
      end
    end
    
    def business_pricing
      publically do
        view = Onetime::App::Views::Pricing.new req, sess, cust
        view[:business] = true
        res.body = view.render
      end
    end
    
    def create_account
      publically("/signup/#{req.params[:planid]}") do
        deny_agents! 
        logic = OT::Logic::CreateAccount.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        sess, cust = logic.sess, logic.cust
        res.redirect '/dashboard'
      end
    end
    
    def authenticate
      publically do
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
            if cust.role?(:colonel)
              res.redirect '/colonel/2nccpefyria0p533zxtks62fa'
            else
              res.redirect '/dashboard'
            end
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

    def generate_apikey
      authenticated do
        logic = OT::Logic::GenerateAPIkey.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        res.redirect app_path('/account')
      end
    end

  end
end
module Onetime
  class App
    
    def login
      publically do
        view = Onetime::App::Views::Login.new req, sess, cust
        res.body = view.render
      end
    end
    
    def pricing
      publically do
        view = Onetime::App::Views::Pricing.new req, sess, cust
        res.body = view.render
      end
    end
    
    def signup
      publically do
        if OT::Plan.plan?(req.params[:planid])
          # NOTE: Not sure why it's necessary to redirect.
          #group_idx = cust.get_persistent_value sess, :initial_pricing_group
          #p [sess.sessid, group_idx]
          #if group_idx.to_s.empty?
          #  res.redirect app_path('/pricing')
          #else
            sess.set_error_message "You're already signed up" if sess.authenticated?
            view = Onetime::App::Views::Signup.new req, sess, cust
            res.body = view.render
          #end
        else
          res.redirect app_path('/')
        end
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
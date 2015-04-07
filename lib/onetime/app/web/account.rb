module Onetime
  class App

    def translations
      publically do
        view = Onetime::App::Views::Translations.new req, sess, cust, locale
        res.body = view.render
      end
    end

    def contributors
      publically do
        if !sess.authenticated? && req.post?
          sess.set_error_message "You'll need to sign in before agreeing."
          res.redirect '/login'
        end
        if sess.authenticated? && req.post?
          if cust.contributor?
            sess.set_info_message "You are already a contributor!"
            res.redirect "/"
          else
            if !req.params[:contributor].to_s.empty?
              if !cust.contributor_at
                cust.contributor = req.params[:contributor]
                cust.contributor_at = Onetime.now.to_i unless cust.contributor_at
                cust.save
              end
              sess.set_info_message "You are now a contributor!"
              res.redirect "/"
            else
              sess.set_error_message "You need to check the confirm box."
              res.redirect '/contributor'
            end
          end
        else
          view = Onetime::App::Views::Contributor.new req, sess, cust, locale
          res.body = view.render
        end
      end
    end

    def forgot
      publically do
        if req.params[:key]
          secret = OT::Secret.load req.params[:key]
          if secret.nil? || secret.verification.to_s != 'true'
            raise OT::MissingSecret if secret.nil?
          else
            view = Onetime::App::Views::Forgot.new req, sess, cust, locale
            view[:verified] = true
            res.body = view.render
          end
        else
          view = Onetime::App::Views::Forgot.new req, sess, cust, locale
          res.body = view.render
        end
      end
    end

    def request_reset
      publically do
        if req.params[:key]
          logic = OT::Logic::ResetPassword.new sess, cust, req.params, locale
          logic.raise_concerns
          logic.process
          res.redirect '/login'
        else
          logic = OT::Logic::ResetPasswordRequest.new sess, cust, req.params, locale
          logic.raise_concerns
          logic.process
          res.redirect '/'
        end
      end
    end

    def pricing
      res.redirect '/signup'
    end

    def signup
      publically do
        if OT::Plan.plan?(req.params[:planid])  # Specific Plan is selected
          sess.set_error_message "You're already signed up" if sess.authenticated?
          view = Onetime::App::Views::Signup.new req, sess, cust, locale
          res.body = view.render
        else                                    # Default signup page
          view = Onetime::App::Views::Plans.new req, sess, cust, locale
          res.body = view.render
        end
      end
    end

    def business_pricing
      publically do
        view = Onetime::App::Views::Plans.new req, sess, cust, locale
        view[:business] = true
        res.body = view.render
      end
    end

    def create_account
      #publically("/signup/#{req.params[:planid]}") do
      publically() do
        deny_agents!
        logic = OT::Logic::CreateAccount.new sess, cust, req.params, locale
        logic.raise_concerns
        logic.process
        #sess, cust = logic.sess, logic.cust
        res.redirect '/'
      end
    end


    def login
      publically do
        view = Onetime::App::Views::Login.new req, sess, cust, locale
        res.body = view.render
      end
    end

    def authenticate
      publically do
        logic = OT::Logic::AuthenticateSession.new sess, cust, req.params, locale
        view = Onetime::App::Views::Login.new req, sess, cust, locale
        if sess.authenticated?
          sess.set_info_message "You are already logged in."
          res.redirect '/'
        else
          if req.post?
            logic.raise_concerns
            logic.process
            sess, cust = logic.sess, logic.cust
            is_secure = Onetime.conf[:site][:ssl]
            res.send_cookie :sess, sess.sessid, sess.ttl, is_secure
            if cust.role?(:colonel)
              res.redirect '/colonel/'
            else
              res.redirect '/'
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
        logic = OT::Logic::DestroySession.new sess, cust, req.params, locale
        logic.raise_concerns
        logic.process
        res.redirect app_path('/')
      end
    end

    def account
      authenticated do
        logic = OT::Logic::ViewAccount.new sess, cust, req.params, locale
        logic.raise_concerns
        logic.process
        view = Onetime::App::Views::Account.new req, sess, cust, locale
        res.body = view.render
      end
    end

    def update_account
      authenticated do
        logic = OT::Logic::UpdateAccount.new sess, cust, req.params, locale
        logic.raise_concerns
        logic.process
        res.redirect app_path('/account')
      end
    end

    def update_subdomain
      authenticated('/account') do
        logic = OT::Logic::UpdateSubdomain.new sess, cust, req.params, locale
        logic.raise_concerns
        logic.process
        res.redirect app_path('/account')
      end
    end

    def generate_apikey
      authenticated do
        logic = OT::Logic::GenerateAPIkey.new sess, cust, req.params, locale
        logic.raise_concerns
        logic.process
        res.redirect app_path('/account')
      end
    end

  end
end

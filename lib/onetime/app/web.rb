
require 'onetime'  # must be required before
require 'onetime/app/web/base'
require 'onetime/app/web/views'
require 'timeout'

module Onetime
  class App
    include Base
    require 'onetime/app/web/info'
    require 'onetime/app/web/account'

    def index
      publically do
        if sess.authenticated?
          dashboard
        else
          view = Onetime::App::Views::Homepage.new req, sess, cust
          sess.event_incr! :homepage
          res.body = view.render
        end
      end
    end

    def test_send_email
      publically do
        OT.info "test_send_email"
        view = OT::Email::TestEmail.new cust
        view.emailer.from = cust.custid
        view.emailer.fromname = ''
        ret = view.deliver_email
        res.body = 'Check your email'
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

    def show_docs
      publically do
        view = Onetime::App::Views::Docs::Api.new req, sess, cust
        res.body = view.render
      end
    end

    def show_docs_secrets
      publically do
        view = Onetime::App::Views::Docs::Api::Secrets.new req, sess, cust
        res.body = view.render
      end
    end

    def show_docs_libs
      publically do
        view = Onetime::App::Views::Docs::Api::Libs.new req, sess, cust
        res.body = view.render
      end
    end

    def receive_feedback
      publically('/feedback') do
        logic = OT::Logic::ReceiveFeedback.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        res.redirect app_path('/feedback')
      end
    end

    def create_secret
      publically('/') do
        logic = OT::Logic::CreateSecret.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        #res.redirect app_path(logic.redirect_uri)
        req.params.clear
        req.params[:key] = logic.metadata.key
        #private_uri # redirect straight to private_uri
        res.redirect logic.redirect_uri
      end
    end

    def secret_uri
      publically do
        deny_agents!
        no_cache!
        logic = OT::Logic::ShowSecret.new sess, cust, req.params
        view = Onetime::App::Views::Shared.new req, sess, cust
        logic.raise_concerns
        logic.process
        view[:is_owner] = logic.secret.owner?(cust)
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
        no_cache!
        logic = OT::Logic::ShowMetadata.new sess, cust, req.params
        logic.raise_concerns
        logic.process
        view = Onetime::App::Views::Private.new req, sess, cust, logic.metadata
        res.body = view.render
        logic.metadata.viewed!
      end
    end

    def burn_secret
      publically do
        deny_agents!
        no_cache!
        logic = OT::Logic::BurnSecret.new sess, cust, req.params
        view = Onetime::App::Views::Burn.new req, sess, cust, logic.metadata
        logic.raise_concerns
        logic.process
        if logic.burn_secret
          res.redirect '/private/' + logic.metadata.key
        else
          view.add_error 'Double check that passphrase' if req.post? && !logic.correct_passphrase
          res.body = view.render
        end
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

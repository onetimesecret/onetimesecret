
require_relative 'web_base'
require_relative 'views'
require_relative '../app_settings'

module Onetime
  module App
    class Page
      include AppSettings
      include Base

      def index
        publically do
          OT.ld "[index] authenticated? #{sess.authenticated?}"
          view = Onetime::App::Views::VuePoint.new req, sess, cust, locale
          sess.event_incr! :get_page
          res.body = view.render
        end
      end

      def customers_only
        authenticated do
          OT.ld "[customers_only] authenticated? #{sess.authenticated?}"
          view = Onetime::App::Views::VuePoint.new req, sess, cust, locale
          sess.event_incr! :get_page
          res.body = view.render
        end
      end

      def colonels_only
        colonels do
          OT.ld "[colonels_only] authenticated? #{sess.authenticated?}"
          view = Onetime::App::Views::VuePoint.new req, sess, cust, locale
          sess.event_incr! :get_page
          res.body = view.render
        end
      end

      def robots_txt
        publically do
          view = Onetime::App::Views::RobotsTxt.new req, sess, cust, locale
          sess.event_incr! :robots_txt
          res.header['Content-Type'] = 'text/plain'
          res.body = view.render
        end
      end
    end

    class Data
      include AppSettings
      include Base
      require 'onetime/app/web/account'

      def receive_feedback
        publically do
          logic = OT::Logic::Misc::ReceiveFeedback.new sess, cust, req.params, locale
          logic.raise_concerns
          logic.process
          res.redirect app_path('/feedback')
        end
      end

      def create_incoming
        publically(req.request_path) do
          if OT.conf[:incoming] && OT.conf[:incoming][:enabled]
            logic = OT::Logic::Incoming::CreateIncoming.new sess, cust, req.params, locale
            logic.raise_concerns
            logic.process
            req.params.clear
            view = Onetime::App::Views::Incoming.new req, sess, cust, locale
            view.add_message view.i18n[:page][:incoming_success_message]
            res.body = view.render
          else
            res.redirect '/'
          end
        end
      end

      def create_secret
        publically('/') do
          logic = OT::Logic::Secrets::CreateSecret.new sess, cust, req.params, locale
          logic.raise_concerns
          logic.process
          req.params.clear
          req.params[:key] = logic.metadata.key
          res.redirect logic.redirect_uri
        end
      end

      def burn_secret
        publically do
          deny_agents!
          no_cache!
          logic = OT::Logic::Secrets::BurnSecret.new sess, cust, req.params, locale
          view = Onetime::App::Views::Burn.new req, sess, cust, locale, logic.metadata
          logic.raise_concerns
          logic.process
          if logic.greenlighted
            res.redirect '/private/' + logic.metadata.key
          else
            view.add_error view.i18n[:COMMON][:error_passphrase] if req.post? && !logic.correct_passphrase
            res.body = view.render
          end
        end
      end

    end

  end
end

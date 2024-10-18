
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

    end

  end
end

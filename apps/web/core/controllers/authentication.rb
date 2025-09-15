# apps/web/core/controllers/authentication.rb

require_relative 'base'

module Core
  module Controllers
    class Authentication
      include Controllers::Base

      def authenticate # rubocop:disable Metrics/AbcSize
        publically('/signin') do
          unless _auth_settings['enabled'] && _auth_settings['signin']
            return disabled_response(req.path)
          end

          # If the request is halted, say for example rate limited, we don't want to
          # allow the browser to refresh and re-submit the form with the login
          # credentials.
          res.no_cache!

          strategy_result = Otto::Security::Authentication::StrategyResult.new(
            session: session,
            user: cust,
            auth_method: 'session',
            metadata: {
              ip: req.client_ipaddress,
              user_agent: req.user_agent
            }
          )

          logic = V2::Logic::Authentication::AuthenticateSession.new strategy_result, req.params, locale
          if session.authenticated?
            session.set_info_message 'You are already logged in.'
            res.redirect '/'
          else
            if req.post? # rubocop:disable Style/IfInsideElse
              logic.raise_concerns
              logic.process
              sess      = logic.sess
              cust      = logic.cust

              res.send_secure_cookie :sess, session.sessid, session.default_expiration
              if cust.role?(:colonel)
                res.redirect '/colonel/'
              else
                res.redirect '/'
              end
            end
          end
        end
      end

      private

      def _auth_settings
        OT.conf.dig('site', 'authentication')
      end
    end
  end
end

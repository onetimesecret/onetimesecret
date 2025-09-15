# apps/web/core/controllers/data_incoming.rb

require_relative 'base'

module Core
  module Controllers
    class DataIncoming
      include Controllers::Base

      def create_incoming
        publically(req.request_path) do
          if OT.conf['incoming'] && OT.conf['incoming']['enabled']
            strategy_result = Otto::Security::Authentication::StrategyResult.new(
              session: session,
              user: cust,
              auth_method: 'session',
              metadata: {
                ip: req.client_ipaddress,
                user_agent: req.user_agent
              }
            )

            logic = V2::Logic::Incoming::CreateIncoming.new strategy_result, req.params, locale
            logic.raise_concerns
            logic.process
            req.params.clear
            view     = Core::Views::Incoming.new req, session, cust, locale
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

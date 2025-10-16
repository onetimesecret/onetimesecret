# apps/web/core/controllers/data_incoming.rb

require_relative 'base'

module Core
  module Controllers
    class DataIncoming
      include Controllers::Base

      def create_incoming
        return res.redirect '/' unless is_enabled

        # TODO: Remove from web/core completely
        logic = V2::Logic::Incoming::CreateIncoming.new(strategy_result, req.params, locale)
        logic.raise_concerns
        logic.process
        req.params.clear
        view = Core::Views::Incoming.new(req, session, cust, locale)
        view.add_message view.i18n[:page][:incoming_success_message]
        res.body = view.render
      end

      def is_enabled
        OT.conf.dig('incoming', 'enabled') || false
      end
    end
  end
end

#  apps/web/core/controllers/data.rb

require_relative 'app_base'

require_relative 'settings'

module Core

  class Data
    include ControllerSettings
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

# apps/web/manifold/controllers/data.rb

require_relative 'base'

module Manifold
  module Controllers
    class Data
      include Controllers::Base

      def rhales_hydration
        publically do
          template_name = req.params[:template] || 'index' # e.g. templates/index.rue

          # Build Rhales context from your app's current state
          ui_context = Onetime::Services::UIContext.new(req, sess, cust, locale)
          endpoint = Rhales::HydrationEndpoint.new(Rhales.configuration, ui_context)

          # Handle different formats like the README example
          result = case req.env['HTTP_ACCEPT']
                   when /application\/javascript/
                     endpoint.render_module(template_name)
                   else
                     endpoint.render_json(template_name)
                   end

          # Set response content type and headers
          res.header['Content-Type'] = result[:content_type]

          # Return the content
          res.body = result[:content]
        end
      end

      def export_window
        publically do
          OT.ld "[export_window] authenticated? #{sess.authenticated?}"
          sess.event_incr! :get_page
          # ExportWindow automatically returns JSON via its render method
          render_view(Manifold::Views::ExportWindow)
        end
      end

      def create_incoming
        publically(req.request_path) do
          if OT.conf[:incoming] && OT.conf[:incoming][:enabled]
            logic    = V2::Logic::Incoming::CreateIncoming.new sess, cust, req.params, locale
            logic.raise_concerns
            logic.process
            req.params.clear
            view     = Manifold::Views::Incoming.new req, sess, cust, locale
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

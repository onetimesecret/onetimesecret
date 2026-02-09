# apps/web/core/controllers/page.rb
#
# frozen_string_literal: true

require_relative 'base'

module Core
  module Controllers
    class Page
      include Controllers::Base

      # /imagine/b79b17281be7264f778c/logo.png
      def imagine
        logic = DomainsAPI::Logic::Domains::GetImage.new(strategy_result, req.params, locale)
        logic.raise_concerns
        logic.process

        res['content-type']   = logic.content_type
        res['content-length'] = logic.content_length
        res.write(logic.image_data)
        res.finish
      end

      def bootstrap_me
        rack_session = req.env['rack.session']
        session_logger.debug 'Exporting bootstrap state',
          {
            session_class: rack_session.class.name,
            session_id: begin
                                  rack_session.id.public_id
            rescue StandardError
                                  'no-id'
            end,
            session_keys: begin
                                    rack_session.keys
            rescue StandardError
                                    []
            end,
            authenticated: rack_session['authenticated'],
            has_external_id: !rack_session['external_id'].nil?,
            authenticated_check: authenticated?,
          }

        # Simplified: BaseView now extracts everything from req
        view                        = Core::Views::BootstrapMe.new(req)
        res.headers['content-type'] = 'application/json; charset=utf-8'
        res.body                    = view.serialized_data.to_json
      end

      def robots_txt
        # Simplified: BaseView now extracts everything from req
        view                        = Core::Views::RobotsTxt.new(req)
        res.headers['content-type'] = 'text/plain'
        res.body                    = view.render
      end

      def favicon
        logic = Core::Logic::Page::GetFavicon.new(strategy_result, req.params, locale)
        logic.raise_concerns
        logic.process

        res['content-type']   = logic.content_type
        res['content-length'] = logic.content_length
        res['cache-control']  = 'public, max-age=86400' # Cache for 1 day
        res.write(logic.icon_data)
        res.finish
      end

      # Dynamic site.webmanifest generated from brand config
      def webmanifest
        brand_conf   = OT.conf['brand'] || {}
        product_name = brand_conf['product_name'] || 'OTS'
        theme_color  = brand_conf['primary_color'] || '#dc4a22'

        manifest = {
          name: product_name,
          short_name: product_name,
          start_url: '/',
          display: 'standalone',
          theme_color: theme_color,
          background_color: '#ffffff',
          icons: [
            {
              src: '/img/onetime-logo-v3-xl.svg',
              sizes: 'any',
              type: 'image/svg+xml',
            },
          ],
        }

        res['content-type']  = 'application/manifest+json'
        res['cache-control'] = 'public, max-age=3600' # Cache for 1 hour
        res.body             = JSON.generate(manifest)
      end
    end
  end
end

# apps/web/core/controllers/page.rb
#
# frozen_string_literal: true

require_relative 'base'

module Core
  module Controllers
    class Page
      include Controllers::Base

      # GET /colonel and /colonel/* (role=colonel).
      #
      # Serves the rebuilt Colonel admin console shell (its own isolated
      # `admin.ts` Vite entry). Since the cutover
      # (docs/specs/colonel-ui/50-cutover-hardening.md) this is unconditional:
      # the admin console is the sole admin frontend and the legacy colonel SPA
      # has been retired. Reuses this core Page controller rather than a second
      # Rack app (D2).
      def colonel
        # Keep parity with Base#index: the view layer serializes homepage_mode.
        req.env['onetime.homepage_mode'] = determine_homepage_mode

        view = Core::Views::AdminPoint.new(req)
        res.body = view.render
      end

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

      def webmanifest
        logic = Core::Logic::Page::GetWebmanifest.new(strategy_result, req.params, locale)
        logic.raise_concerns
        logic.process

        res['content-type']  = logic.content_type
        # Shorter TTL than the static pack: this manifest is brand-aware (it
        # overlays BRAND_PRODUCT_NAME / BRAND_PRIMARY_COLOR at request time), so
        # cap caching at 1h to bound how long an env-config change can be stale
        # in CDNs/browsers. Manifests are fetched infrequently, so this is cheap.
        res['cache-control'] = 'public, max-age=3600' # 1 hour
        res.write(logic.manifest_json)
        res.finish
      end

      def favicon
        logic = Core::Logic::Page::GetFavicon.new(strategy_result, req.params, locale)
        logic.raise_concerns
        logic.process

        if logic.redirect_url
          res['cache-control'] = 'public, max-age=86400'
          res.redirect(logic.redirect_url, 302)
        else
          res['content-type']   = logic.content_type
          res['content-length'] = logic.content_length
          res['cache-control']  = 'public, max-age=86400' # Cache for 1 day
          res.write(logic.icon_data)
          res.finish
        end
      end
    end
  end
end

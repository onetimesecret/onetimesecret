# apps/web/core/controllers/page.rb
#
# frozen_string_literal: true

require 'onetime/application/error_correlation'

require_relative 'base'

module Core
  module Controllers
    class Page
      include Controllers::Base

      # ADR-046 step 7. `retry_after` reaches the client as the Retry-After
      # header through Onetime::Middleware::RetryAfterHeader.
      SNAPSHOT_ORDERING_UNAVAILABLE = {
        error: 'Snapshot ordering unavailable',
        error_type: 'SnapshotOrderingUnavailable',
        retry_after: 5,
      }.freeze

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

        view     = Core::Views::AdminPoint.new(req)
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
        # Guard the debug payload behind OT.debug? — Ruby always evaluates
        # method arguments, so an ungated call would run the full
        # CustomerSessionEvaluator (customer load + active-session gate) on
        # every request via `authenticated?`, even when the logger is silenced.
        if OT.debug?
          rack_session = req.env['rack.session']
          session_logger.debug 'Exporting bootstrap state',
            {
              session_class: rack_session.class.name,
              authenticated: rack_session['authenticated'] == true,
              has_external_id: !rack_session['external_id'].nil?,
              authenticated_check: authenticated?,
              request_id: req.env['HTTP_X_REQUEST_ID'],
            }
        end

        # Simplified: BaseView now extracts everything from req
        view                         = Core::Views::BootstrapMe.new(req)
        data                         = view.serialized_data
        log_bootstrap_verification
        res.headers['content-type']  = 'application/json; charset=utf-8'
        # On the 503 as well: a stored failure replayed later would read as a
        # fresh one (ADR-046, "Response caching").
        res.headers['cache-control'] = 'private, no-store'

        if snapshot_unordered?(data)
          res.status = 503
          res.body   = Onetime::Application::ErrorCorrelation.apply(
            SNAPSHOT_ORDERING_UNAVAILABLE.dup, req.env
          ).to_json
          return
        end

        res.body = data.to_json
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

      private

      # What verifying the session cost this poll, for the #4463 rollout
      # review (#4455): the queries and writes ActiveSessionGate issued
      # against the active-session table, and whether the route was passive.
      # A passive poll of a live session reads `queries: 1, writes: 0`; a
      # write here means an expired row was removed, which is the one write a
      # poll is meant to make.
      #
      # One line per poll that carried a session claim. A visitor with no
      # session is skipped: it is most of the traffic and verifies nothing.
      # The join is the request id; the line carries no session identifier.
      def log_bootstrap_verification
        verdict = req.env[Onetime::CustomerSessionEvaluator::ENV_KEY]
        return if verdict.nil? || verdict.anonymous?

        stats = req.env[Onetime::ActiveSessionGate::STATS_ENV_KEY] || {}
        session_logger.info 'Bootstrap verification',
          {
            passive: Onetime::SessionActivity.passive?(req.env),
            verdict: verdict.status,
            reason: verdict.reason,
            active_session_queries: stats.fetch(:queries, 0),
            active_session_writes: stats.fetch(:writes, 0),
            request_id: req.env['HTTP_X_REQUEST_ID'],
          }
      rescue StandardError
        nil
      end

      # A snapshot that reports a session must carry the ordering pair
      # (ADR-046): the server never labels an unversioned payload as ordered,
      # and never hands an ordered tab a session snapshot it cannot place. The
      # client treats the 503 as a failed refresh and keeps its last accepted
      # state.
      #
      # A snapshot that reports NO session is served as it is, pair or not.
      # Session expiry, revocation and logout reach the tab that way, and an
      # ordering outage must never be able to withhold them.
      def snapshot_unordered?(data)
        reports_session = data['authenticated'] == true || data['awaiting_mfa'] == true
        reports_session && data['snapshot_version'].nil?
      end
    end
  end
end

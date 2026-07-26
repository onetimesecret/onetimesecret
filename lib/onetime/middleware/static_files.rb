# lib/onetime/middleware/static_files.rb
#
# frozen_string_literal: true

#
# Static file serving middleware for the Onetime Secret application.
# Provides static file serving capabilities which can be used when
# running without a reverse proxy.

require 'rack'

module Onetime
  module Middleware
    # Static file serving middleware for Onetime Secret in production
    #
    # This middleware handles serving static assets in production environments:
    # - Serves files from the public/web directory
    # - Handles common static paths like /dist, /img, etc.
    # - Enables the Vue frontend to be served in a production environment
    #
    # While a reverse proxy (like nginx) often handles static files in production,
    # this middleware provides fallback capability for simpler deployments.
    #
    class StaticFiles
      # Root-served brand-pack asset URLs that can be overlaid by a brand pack
      # (site.brand_pack / site.brand_assets_dir, #3739). /dist is the app build
      # output and is NEVER overlaid. Every URL here is MANDATORY — the tracked
      # default pack is drift-guarded to carry all of them — so the base layer
      # serves them unconditionally.
      BRAND_PACK_URLS = %w[
        /favicon.svg /safari-pinned-tab.svg /apple-touch-icon.png
        /icon-192.png /icon-512.png /social-preview.png
      ].freeze

      # Optional pack-carried masthead/header logo, served overlay-first at a
      # stable URL so a pack can ship its OWN logo image instead of hosting it
      # externally (#3774). Kept SEPARATE from BRAND_PACK_URLS because it is
      # optional: the neutral default pack ships no logo, so these URLs are
      # existence-filtered on BOTH layers — listing a missing file in the
      # unconditional base layer would 404-shadow the URL instead of letting it
      # fall through. A pack opts in by (a) carrying brand-logo.svg and/or
      # brand-logo.png in its directory AND (b) pointing brand.logo_url
      # (brand.yaml manifest or BRAND_LOGO_URL) at it, e.g.
      # `logo_url: "/brand-logo.svg"`. The file alone is inert until logo_url
      # references it; normalize_brand root-relativizes the path so it resolves
      # identically on every route. Note: a root-relative logo renders in the
      # web UI but is omitted from emails (which need an absolute URL) — the
      # same pre-existing caveat normalize_brand already warns about at boot.
      BRAND_PACK_LOGO_URLS = %w[/brand-logo.svg /brand-logo.png].freeze

      # The wrapped Rack application
      # @return [#call] The Rack application instance passed to this middleware
      attr_reader :app

      # Initialize the static files middleware
      #
      # @param app [#call] The Rack application to wrap
      def initialize(app)
        @app      = app
        @rack_app = setup_static_files
      end

      # Process an HTTP request through the static files middleware stack
      # Serves static files if path matches, otherwise delegates to the app
      #
      # @param env [Hash] Rack environment hash containing request information
      # @return [Array] Standard Rack response array [status, headers, body]
      def call(env)
        @rack_app.call(env)
      end

      private

      # Configure the static file serving middleware stack
      #
      # Creates a Rack middleware stack that serves static files from specific paths
      # and delegates all other requests to the wrapped application.
      #
      # @return [#call] Configured Rack application with static file handling
      def setup_static_files
        # Store reference to original app for use inside builder block
        # This is necessary because the Rack::Builder block runs in a different context
        app_instance        = @app
        middleware_settings = Onetime.conf.dig('site', 'middleware') || {}

        Rack::Builder.new do
          # Configure static file middleware to serve files from public/web directory
          # Only serve specific paths that contain static assets
          if middleware_settings['static_files']
            Onetime.ld '[StaticFiles] Enabling StaticFiles middleware'
            require 'rack/static'

            # Brand-pack resolution ALWAYS lands on a pack (#3774). The base
            # brand layer for BRAND_PACK_URLS now serves from the resolved DEFAULT
            # pack (public/branding/default) instead of loose public/web files.
            base_dir    = Onetime.brand_pack_dir(Onetime::DEFAULT_BRAND_PACK)
            overlay_dir = Onetime.brand_overlay_dir

            # Selected-pack overlay layer (#3739). Mounted BEFORE the base layer
            # so it is outermost in Rack::Builder and matches first. Only present
            # when an operator SELECTED a pack distinct from the default — a
            # partial selected pack then falls through to the default base for the
            # files it omits. Only files that actually EXIST in the overlay dir
            # are listed: Rack::Static matches by URL prefix, not file existence,
            # so a listed URL with a missing file would 404 instead of falling
            # through. Existence is resolved once at boot — changing packs (or
            # adding overlay files) needs a restart.
            #
            # Note the existence filter here applies to the MANDATORY BRAND_PACK_URLS
            # too, not just the optional logo URLs: "unconditional" serving (see the
            # BRAND_PACK_URLS comment) is a BASE-layer property. A selected pack that
            # omits a mandatory file simply isn't listed in this overlay layer, so it
            # falls through to the default base for that file.
            if overlay_dir && base_dir && overlay_dir != base_dir
              overlay_urls = (BRAND_PACK_URLS + BRAND_PACK_LOGO_URLS).select { |u| File.exist?(File.join(overlay_dir, u)) }
              unless overlay_urls.empty?
                Onetime.ld "[StaticFiles] Brand overlay active: #{overlay_dir} (#{overlay_urls.size} file(s))"
                use Rack::Static, urls: overlay_urls, root: overlay_dir
              end
            end

            # Base brand layer: the resolved default pack (#3774). No public/web
            # fallback — the default pack is tracked and drift-guarded, so if it
            # is somehow absent (a broken checkout) the layer is simply skipped
            # and brand URLs fall through to the app rather than serving stale
            # public/web files. /favicon.ico and /site.webmanifest are
            # intentionally NOT listed: they are served by Core::Controllers::Page
            # routes so per-custom-domain icons, brand.favicon_url redirects, and
            # brand-aware manifest fields keep working.
            if base_dir
              # Mandatory assets serve unconditionally (drift-guarded present);
              # the optional logo URLs are existence-filtered so an absent logo
              # (the neutral default pack) falls through instead of 404-shadowing.
              base_logo_urls = BRAND_PACK_LOGO_URLS.select { |u| File.exist?(File.join(base_dir, u)) }
              Onetime.ld "[StaticFiles] Base brand layer: #{base_dir}"
              use Rack::Static, urls: BRAND_PACK_URLS + base_logo_urls, root: base_dir
            else
              Onetime.le '[StaticFiles] default brand pack not found; brand assets will 404'
            end

            # App/build assets — never overlaid by a brand pack. Only /dist
            # (Vite build output) remains in public/web; the legacy /img and /v3
            # image trees were retired once brand assets moved to the brand pack
            # (public/branding/<pack>). Root against HOME rather than CWD (puma's
            # working dir is not guaranteed).
            use Rack::Static,
              urls: ['/dist'],
              root: File.join(Onetime::HOME, 'public', 'web')
          end

          # All non-static requests pass through to the original application
          run ->(env) { app_instance.call(env) }
        end.to_app
      end
    end
  end
end

# apps/web/core/logic/page/get_webmanifest.rb
#
# frozen_string_literal: true

require 'json'
require_relative '../base'

module Core
  module Logic
    module Page
      # GetWebmanifest - Serve a brand-aware PWA web manifest.
      #
      # Reads the on-disk neutral manifest from the resolved brand pack
      # (Onetime.brand_asset_path('site.webmanifest') — the default pack
      # public/branding/default, or a selected BRAND_PACK / BRAND_ASSETS_DIR pack)
      # and overlays the site-level brand fields from OT.conf:
      #
      #   - name / short_name <- brand.product_name (when set)
      #   - theme_color       <- brand.primary_color (when set)
      #
      # When no brand config is present the neutral file is served unchanged, so
      # a vanilla self-hosted install still gets a valid, brand-agnostic manifest
      # ("Secure Links"). Icons are left as the on-disk paths (override by replacing the
      # files). This mirrors the favicon precedence: per-deployment brand config
      # over neutral defaults, without OTS branding ever shipping as the default.
      class GetWebmanifest < Core::Logic::Base
        attr_reader :manifest_json, :content_type

        CONTENT_TYPE = 'application/manifest+json'

        # Minimal neutral fallback if the on-disk manifest is missing/corrupt.
        NEUTRAL_FALLBACK = {
          'name' => 'Secure Links',
          'short_name' => 'Secure Links',
          'icons' => [
            { 'src' => '/icon-192.png', 'sizes' => '192x192', 'type' => 'image/png', 'purpose' => 'any' },
            { 'src' => '/icon-512.png', 'sizes' => '512x512', 'type' => 'image/png', 'purpose' => 'any' },
            { 'src' => '/icon-512.png', 'sizes' => '512x512', 'type' => 'image/png', 'purpose' => 'maskable' },
          ],
          'theme_color' => '#3B82F6',
          'background_color' => '#ffffff',
          'display' => 'standalone',
          'start_url' => '/',
        }.freeze

        def process_params
          @brand        = OT.conf.fetch('brand', {}) || {}
          @content_type = CONTENT_TYPE
        end

        def raise_concerns
          # Public endpoint; no authorization required.
        end

        def process
          manifest = load_base_manifest

          product_name  = @brand['product_name']
          primary_color = @brand['primary_color']

          unless product_name.to_s.strip.empty?
            manifest['name']       = product_name
            manifest['short_name'] = product_name
          end
          manifest['theme_color'] = primary_color unless primary_color.to_s.strip.empty?

          @manifest_json = JSON.generate(manifest)
        end

        def success_data
          manifest_json
        end

        private

        # Re-reads and re-parses the on-disk manifest per request by design; do
        # NOT memoize at boot. The resolved path IS constant per deployment (it
        # derives only from global OT.conf brand_pack/brand_assets_dir, not from
        # the request or custom domain), so a boot-time cache is technically
        # sound — but not worth it: this endpoint is cold (browser-cached, 1h CDN
        # max-age; see controller), so the saved syscall+parse is unmeasurable,
        # while per-request re-read keeps a swapped BRAND_ASSETS_DIR volume live
        # without a restart. Any future cache MUST dup before the process overlay
        # mutates name/short_name/theme_color (same trap as the rescue branch).
        def load_base_manifest
          path = Onetime.brand_asset_path('site.webmanifest')
          JSON.parse(File.read(path))
        rescue StandardError => ex
          OT.le "[GetWebmanifest] Falling back to neutral manifest: #{ex.message}"
          # Dup so per-request overlay never mutates the frozen constant.
          JSON.parse(JSON.generate(NEUTRAL_FALLBACK))
        end
      end
    end
  end
end

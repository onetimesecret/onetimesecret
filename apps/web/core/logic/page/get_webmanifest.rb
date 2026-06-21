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
      # Reads the on-disk neutral manifest (public/web/site.webmanifest, which is
      # itself overridable via the docker/public build overlay or a runtime
      # file mount) and overlays the site-level brand fields from OT.conf:
      #
      #   - name / short_name <- brand.product_name (when set)
      #   - theme_color       <- brand.primary_color (when set)
      #
      # When no brand config is present the neutral file is served unchanged, so
      # a vanilla self-hosted install still gets a valid, brand-agnostic manifest
      # ("My App"). Icons are left as the on-disk paths (override by replacing the
      # files). This mirrors the favicon precedence: per-deployment brand config
      # over neutral defaults, without OTS branding ever shipping as the default.
      class GetWebmanifest < Core::Logic::Base
        attr_reader :manifest_json, :content_type

        CONTENT_TYPE = 'application/manifest+json'

        # Minimal neutral fallback if the on-disk manifest is missing/corrupt.
        NEUTRAL_FALLBACK = {
          'name' => 'My App',
          'short_name' => 'My App',
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

        def load_base_manifest
          path = File.join(OT.conf.dig('site', 'public_dir') || 'public/web', 'site.webmanifest')
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

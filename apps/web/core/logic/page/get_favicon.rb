# apps/web/core/logic/page/get_favicon.rb
#
# frozen_string_literal: true

require 'chunky_png'
require_relative '../base'

module Core
  module Logic
    module Page
      # GetFavicon - Serve custom favicon for branded domains
      #
      # This logic class dynamically serves either:
      # 1. Custom favicon from the custom domain's icon field (if available)
      # 2. Default favicon from public/img/
      #
      # For custom favicons, it checks for a cached resized version (32x32)
      # stored in custom_domain.icon['encoded_favicon']. If not found, it
      # generates and caches one from the original icon.
      #
      # Uses env vars set by DetectHost and DomainStrategy middlewares:
      # - env['onetime.domain_strategy'] - Domain classification (:custom, :canonical, etc.)
      # - env['onetime.display_domain'] - Normalized domain name
      #
      class GetFavicon < Core::Logic::Base
        attr_reader :custom_domain, :icon_data, :content_type, :content_length, :use_default

        FAVICON_SIZE = 32 # 32x32 pixels

        def process_params
          # Get domain strategy determined by DomainStrategy middleware
          domain_strategy = req.env['onetime.domain_strategy']
          display_domain  = req.env['onetime.display_domain']

          OT.ld "[GetFavicon] strategy=#{domain_strategy} domain=#{display_domain}"

          # Only try to load custom domain if strategy indicates it's a custom domain
          if domain_strategy == :custom
            @custom_domain = Onetime::CustomDomain.from_display_domain(display_domain)
          end

          @use_default = true # Default to OTS favicon
        end

        def raise_concerns
          # No authorization required - public endpoint
          # But we need to check if custom domain has an icon
          return unless custom_domain

          # Check if custom domain has an icon uploaded
          icon_filename = custom_domain.icon['filename']
          return unless icon_filename && !icon_filename.empty?

          # We have a custom icon - don't use default
          @use_default = false
        end

        def process
          if use_default
            # Serve default favicon
            serve_default_favicon
          else
            # Serve custom favicon from Redis (cached or generate)
            serve_custom_favicon
          end
        end

        private

        def serve_custom_favicon
          # Check if we have a cached favicon-sized version
          cached_favicon = custom_domain.icon['encoded_favicon']

          if cached_favicon.to_s.empty?
            # No cached version - generate one
            OT.ld "[GetFavicon] No cached favicon for #{custom_domain.display_domain}, generating..."
            generate_and_cache_favicon
          else
            # Use cached version
            OT.ld "[GetFavicon] Serving cached favicon for #{custom_domain.display_domain}"
            @icon_data = Base64.strict_decode64(cached_favicon)
          end

          @content_type   = 'image/png' # Resized favicons are always PNG
          @content_length = icon_data.bytesize.to_s
        end

        def generate_and_cache_favicon
          original_encoded = custom_domain.icon['encoded']
          original_type    = custom_domain.icon['content_type']

          # Decode original image
          original_data = Base64.strict_decode64(original_encoded)

          # Try to resize based on content type
          resized_data = if original_type == 'image/png'
                           resize_png(original_data)
                         else
                           # For non-PNG formats, use original for now
                           # TODO: Add support for JPEG/WebP/etc with mini_magick or ruby-vips
                           OT.ld "[GetFavicon] Non-PNG format #{original_type}, using original"
                           original_data
                         end

          # Cache the resized favicon
          encoded_favicon                       = Base64.strict_encode64(resized_data)
          custom_domain.icon['encoded_favicon'] = encoded_favicon

          @icon_data = resized_data

          OT.info "[GetFavicon] Generated and cached favicon for #{custom_domain.display_domain}"
        rescue StandardError => ex
          # If resizing fails, fall back to original
          OT.le "[GetFavicon] Failed to resize favicon: #{ex.message}"
          @icon_data = Base64.strict_decode64(original_encoded)
        end

        def resize_png(png_data)
          # Load PNG with ChunkyPNG
          image = ChunkyPNG::Image.from_blob(png_data)

          # Resize to FAVICON_SIZE x FAVICON_SIZE
          resized = image.resample_nearest_neighbor(FAVICON_SIZE, FAVICON_SIZE)

          # Return PNG data
          resized.to_blob
        end

        def serve_default_favicon
          # Read default favicon from public directory
          favicon_path = File.join(OT.conf[:site][:public_dir] || 'public', 'favicon.ico')

          if File.exist?(favicon_path)
            @icon_data      = File.binread(favicon_path)
            @content_type   = 'image/x-icon'
            @content_length = icon_data.bytesize.to_s
            OT.ld '[GetFavicon] Serving default favicon'
          else
            # Fallback to empty response if default doesn't exist
            @icon_data      = ''
            @content_type   = 'image/x-icon'
            @content_length = '0'
            OT.le "[GetFavicon] Default favicon not found at #{favicon_path}"
          end
        end

        def success_data
          icon_data
        end
      end
    end
  end
end

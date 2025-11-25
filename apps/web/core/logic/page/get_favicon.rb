# apps/web/core/logic/page/get_favicon.rb
#
# frozen_string_literal: true

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
      # This allows branded custom domains to show their own favicon
      # instead of the OTS default orange S icon.
      #
      # Uses env vars set by DetectHost and DomainStrategy middlewares:
      # - env['onetime.domain_strategy'] - Domain classification (:custom, :canonical, etc.)
      # - env['onetime.display_domain'] - Normalized domain name
      #
      class GetFavicon < Core::Logic::Base
        attr_reader :custom_domain, :icon_data, :content_type, :content_length, :use_default

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
            # Serve custom favicon from Redis
            serve_custom_favicon
          end
        end

        private

        def serve_custom_favicon
          # Get icon data from custom domain
          encoded_content = custom_domain.icon['encoded']
          @content_type   = custom_domain.icon['content_type'] || 'image/x-icon'

          # Decode base64 content
          @icon_data       = Base64.strict_decode64(encoded_content)
          @content_length  = icon_data.bytesize.to_s

          OT.info "[GetFavicon] Serving custom favicon for #{custom_domain.display_domain}"
        end

        def serve_default_favicon
          # Read default favicon from public directory
          favicon_path = File.join(OT.conf[:site][:public_dir] || 'public', 'favicon.ico')

          if File.exist?(favicon_path)
            @icon_data      = File.binread(favicon_path)
            @content_type   = 'image/x-icon'
            @content_length = icon_data.bytesize.to_s
            OT.ld "[GetFavicon] Serving default favicon"
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

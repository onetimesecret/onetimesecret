# apps/web/auth/helpers/vite_assets.rb

module AuthHelpers
  module ViteAssets
    # Check if we're in development mode based on configuration
    def frontend_development?
      OT.conf.dig('development', 'enabled') || false
    end

    # Generate HTML tags for all required Vite assets
    def vite_assets(nonce: nil)
      if frontend_development?
        development_assets(nonce)
      else
        production_assets(nonce)
      end
    end

    # Get CSS file path from Vite manifest (legacy method for backward compatibility)
    def vite_css_path
      return '/dist/assets/style.css' if frontend_development?

      manifest_path = File.join(Dir.pwd, 'public', 'web', 'dist', '.vite', 'manifest.json')

      return '/dist/assets/style.css' unless File.exist?(manifest_path)

      begin
        manifest = JSON.parse(File.read(manifest_path))
        style_entry = manifest['style.css']

        if style_entry && style_entry['file']
          "/dist/#{style_entry['file']}"
        else
          # Fallback: look for CSS in main entry
          main_entry = manifest['main.ts']
          if main_entry && main_entry['css']&.any?
            "/dist/#{main_entry['css'].first}"
          else
            '/dist/assets/style.css' # fallback
          end
        end
      rescue JSON::ParserError, StandardError
        '/dist/assets/style.css' # fallback
      end
    end

    private

    # Development mode assets - load from Vite dev server
    def development_assets(nonce)
      assets = []
      assets << build_script_tag('main.ts', nonce)
      assets << build_script_tag('@vite/client', nonce)
      assets.join("\n")
    end

    # Production mode assets - load from compiled manifest
    def production_assets(nonce)
      manifest_path = File.join(Dir.pwd, 'public', 'web', 'dist', '.vite', 'manifest.json')

      unless File.exist?(manifest_path)
        msg = 'Vite manifest.json not found. Run `pnpm run build`'
        return error_script(nonce, msg)
      end

      begin
        manifest = JSON.parse(File.read(manifest_path))
        main_entry = manifest['main.ts']
        style_entry = manifest['style.css']

        return error_script(nonce, 'Main entry not found in Vite manifest') unless main_entry

        assets = []
        assets << build_script_tag(main_entry['file'], nonce)

        # Handle CSS from main entry
        if main_entry['css']&.any?
          main_entry['css'].each do |css_file|
            assets << build_css_tag(css_file, nonce)
          end
        end

        # Handle separate style.css entry
        if style_entry && style_entry['file']
          assets << build_css_tag(style_entry['file'], nonce)
        end

        assets.concat(build_font_preloads(manifest, nonce))
        assets.join("\n")
      rescue JSON::ParserError, StandardError => e
        error_script(nonce, "Error parsing manifest: #{e.message}")
      end
    end

    # Build a script tag for JavaScript assets
    def build_script_tag(file, nonce)
      nonce_attr = nonce ? %( nonce="#{nonce}") : ''
      %(<script type="module"#{nonce_attr} src="/dist/#{file}"></script>)
    end

    # Build a link tag for CSS assets
    def build_css_tag(file, nonce)
      return unless file

      nonce_attr = nonce ? %( nonce="#{nonce}") : ''
      %(<link rel="stylesheet"#{nonce_attr} href="/dist/#{file}">)
    end

    # Build preload link tags for font assets
    def build_font_preloads(manifest, nonce)
      manifest.values
        .select { |entry| entry['file'] =~ /\.(woff2?|ttf|otf|eot)$/ }
        .map do |font|
          ext = File.extname(font['file']).delete('.')
          nonce_attr = nonce ? %( nonce="#{nonce}") : ''
          %(<link rel="preload"#{nonce_attr} href="/dist/#{font['file']}" as="font" type="font/#{ext}" crossorigin>)
        end
    end

    # Build an error script tag when asset loading fails
    def error_script(nonce, message)
      nonce_attr = nonce ? %( nonce="#{nonce}") : ''
      %(<script#{nonce_attr}>console.warn("#{message}")</script>)
    end
  end
end

# apps/web/auth/helpers/vite_assets.rb

module AuthHelpers
  module ViteAssets
    # Get CSS file path from Vite manifest
    def vite_css_path
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
  end
end

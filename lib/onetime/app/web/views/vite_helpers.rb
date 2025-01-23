# lib/onetime/app/web/views/vite_helpers.rb

module Onetime
  module App
    module Views
      module ViteHelpers # rubocop:disable Style/Documentation

        def vite_assets(nonce: nil)
          nonce ||= self[:nonce] # we allow overriding the nonce for testing
          manifest_path = File.join(PUBLIC_DIR, 'dist', '.vite', 'manifest.json')

          unless File.exist?(manifest_path)
            msg = "Vite %s not found. Run `pnpm run build`"
            OT.le msg % manifest_path
            return error_script(nonce, msg % 'manifest.json')
          end

          @manifest_cache ||= JSON.parse(File.read(manifest_path))
          main_entry = @manifest_cache["main.ts"]

          return error_script(nonce, "Main entry not found in Vite manifest") unless main_entry

          assets = build_asset_tags(main_entry, nonce)

          # require 'pry-byebug'; binding.pry

          if assets.empty?
            OT.le "No assets found in Vite manifest at #{manifest_path}"
            return error_script(nonce, "No assets found for main entry point in Vite manifest")
          end

          assets.join("\n")
        end

        def build_asset_tags(entry, nonce)
          assets = []
          assets << build_script_tag(entry['file'], nonce)

          # Add CSS from main entry
          if entry['css']&.any?
            entry['css'].each do |css_file|
              assets << build_css_tag(css_file, nonce)
            end
          end

          assets.concat(build_font_preloads(@manifest_cache, nonce))
          assets
        end

        def build_script_tag(file, nonce)
          %(<script type="module" nonce="#{nonce}" src="/dist/#{file}"></script>)
        end

        def build_css_tag(file, nonce)
          return unless file
          %(    <link rel="stylesheet" nonce="#{nonce}" href="/dist/#{file}">)
        end

        def build_font_preloads(manifest, nonce)
          manifest.values
            .select { |entry| entry['file'] =~ /\.(woff2?|ttf|otf|eot)$/ }
            .map do |font|
              ext = File.extname(font['file']).delete('.')
              %(    <link rel="preload" nonce="#{nonce}" href="/dist/#{font['file']}" as="font" type="font/#{ext}" crossorigin>)
            end
        end

        def error_script(nonce, message)
          %(<script nonce="#{nonce}">console.warn("#{message}")</script>)
        end
      end
    end
  end
end

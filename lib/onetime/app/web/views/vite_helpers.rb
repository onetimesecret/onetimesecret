# lib/onetime/app/web/views/vite_helpers.rb

module Onetime
  module App
    module Views
      module ViteHelpers # rubocop:disable Style/Documentation

        def vite_assets(nonce: nil)
          nonce ||= self[:nonce] # we allow overriding the nonce for testing

          manifest_path = File.join(PUBLIC_DIR, 'dist', '.vite', 'manifest.json')
                    unless File.exist?(manifest_path)
            OT.le "Vite manifest not found at #{manifest_path}. Run `pnpm run build`"
            return "<script nonce=\"#{nonce}\">console.warn(\"Vite manifest not found. Run `pnpm run build`\")</script>"
          end

          @manifest_cache ||= JSON.parse(File.read(manifest_path))

          assets = []

          # Find the main entry point (assuming it's named "main.ts" in your manifest)
          main_entry = @manifest_cache["main.ts"]

          if main_entry
            # Add the main JavaScript file
            assets << %(<script type="module" nonce="#{nonce}" src="/dist/#{main_entry['file']}"></script>)

            # Add the main CSS file if it exists
            if main_entry['css'] && main_entry['css'].first
              assets << %(    <link rel="stylesheet" nonce="#{nonce}" href="/dist/#{main_entry['css'].first}">)
            end

            # Add preloads for font files
            font_files = @manifest_cache.values.select { |v| v['file'] =~ /\.(woff2?|ttf|otf|eot)$/ }
            font_files.each do |font|
              file_extension = File.extname(font['file']).delete('.')
              assets << %(    <link rel="preload" nonce="#{nonce}" href="/dist/#{font['file']}" as="font" type="font/#{file_extension}" crossorigin>)
            end
          else
            OT.le "Main entry point not found in Vite manifest at #{manifest_path}"
            return %W{<script nonce="#{nonce}">console.warn("Main entry point not found in Vite manifest")</script>}
          end

          if assets.empty?
            OT.le "No assets found for main entry point in Vite manifest at #{manifest_path}"
            return %W{<script nonce="#{nonce}">console.warn("No assets found for main entry point in Vite manifest")</script>}
          end

          assets.join("\n")
        end

      end
    end
  end
end

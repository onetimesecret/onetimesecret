# apps/web/core/views/helpers/vite_helpers.rb

module Core

  ##
  # ViteManifest - Asset Management for Multiple Vite Configurations
  #
  # Supports two Vite build configurations:
  # 1. Default (vite.config.ts) - Consolidated assets with separate style entry
  # 2. Alternative (vite.config.local.ts) - Same, without the hash in the filenames
  #
  # Asset Loading Strategy:
  # - Checks main.ts entry for embedded CSS references
  # - Checks for separate style.css entry
  # - Maintains backward compatibility with both manifest formats
  # - Handles font preloading for both configurations
  #
  # @see vite.config.ts
  # @see vite.config.local.ts
  #
  module ViteManifest # rubocop:disable Style/Documentation

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
      style_entry = @manifest_cache["style.css"] # may not exist

      return error_script(nonce, "Main entry not found in Vite manifest") unless main_entry

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

      assets.concat(build_font_preloads(@manifest_cache, nonce))
      assets.join("\n")
    end

    private

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

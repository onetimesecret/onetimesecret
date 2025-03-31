# apps/web/core/views/helpers/vite_manifest.rb

module Core
  module Views
    # ViteManifest handles asset loading for Vite-managed frontend assets.
    #
    # This module loads JavaScript, CSS, and font assets based on the Vite manifest,
    # supporting both production and development configurations. It handles the
    # complexities of CSS bundling and font preloading.
    #
    module ViteManifest

      # Generates HTML tags for all required Vite assets.
      #
      # @param nonce [String, nil] Content Security Policy nonce
      # @return [String] HTML tags for all required assets
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

      # Builds a script tag for JavaScript assets.
      #
      # @param file [String] Asset file path
      # @param nonce [String] Content Security Policy nonce
      # @return [String] HTML script tag
      def build_script_tag(file, nonce)
        %(<script type="module" nonce="#{nonce}" src="/dist/#{file}"></script>)
      end

      # Builds a link tag for CSS assets.
      #
      # @param file [String] CSS file path
      # @param nonce [String] Content Security Policy nonce
      # @return [String, nil] HTML link tag or nil if file is nil
      def build_css_tag(file, nonce)
        return unless file
        %(    <link rel="stylesheet" nonce="#{nonce}" href="/dist/#{file}">)
      end

      # Builds preload link tags for font assets.
      #
      # @param manifest [Hash] Vite manifest data
      # @param nonce [String] Content Security Policy nonce
      # @return [Array<String>] Array of HTML preload link tags
      def build_font_preloads(manifest, nonce)
        manifest.values
          .select { |entry| entry['file'] =~ /\.(woff2?|ttf|otf|eot)$/ }
          .map do |font|
            ext = File.extname(font['file']).delete('.')
            %(    <link rel="preload" nonce="#{nonce}" href="/dist/#{font['file']}" as="font" type="font/#{ext}" crossorigin>)
        end
      end

      # Builds an error script tag when asset loading fails.
      #
      # @param nonce [String] Content Security Policy nonce
      # @param message [String] Error message
      # @return [String] HTML script tag with error message
      def error_script(nonce, message)
        %(<script nonce="#{nonce}">console.warn("#{message}")</script>)
      end
    end
  end
end

# apps/web/core/views/helpers/vite_manifest.rb
#
# frozen_string_literal: true

require 'onetime/logger_methods'

module Core
  module Views
    # ViteManifest handles asset loading for Vite-managed frontend assets.
    #
    # This module loads JavaScript, CSS, and font assets based on the Vite manifest,
    # supporting both production and development configurations. It handles the
    # complexities of CSS bundling and font preloading.
    #
    module ViteManifest
      include Onetime::LoggerMethods

      # Public directory for web assets
      PUBLIC_DIR = File.join(ENV.fetch('ONETIME_HOME', '.'), 'public', 'web').freeze
      # Generates HTML tags for all required Vite assets.
      #
      # @param nonce [String, nil] Content Security Policy nonce
      # @param development [Boolean] Whether to use development mode
      # @param entry [String] Vite manifest entry key to resolve. Defaults to
      #   'main.ts' (the customer bundle); the admin shell passes 'admin.ts'.
      #   The key is the source path relative to the Vite root (src/), which is
      #   why it is the '.ts' filename and not the input object key.
      # @return [String] HTML tags for all required assets
      def vite_assets(nonce: nil, development: nil, entry: 'main.ts')
        nonce     ||= self['nonce'] if respond_to?(:[]) # we allow overriding the nonce for testing
        development = self['frontend_development'] if development.nil? && respond_to?(:[])

        # Development mode: direct Vite dev server links
        if development
          return build_dev_assets(nonce, entry)
        end

        # Production mode: use manifest
        build_prod_assets(nonce, entry)
      end

      private

      # Builds development mode asset tags (Vite dev server)
      #
      # @param nonce [String] Content Security Policy nonce
      # @param entry [String] Vite entry to serve (e.g. 'main.ts' or 'admin.ts')
      # @return [String] HTML tags for dev assets
      def build_dev_assets(nonce, entry = 'main.ts')
        <<~HTML.chomp
          <script type="module" nonce="#{nonce}" src="/dist/#{entry}"></script>
          <script type="module" nonce="#{nonce}" src="/dist/@vite/client"></script>
        HTML
      end

      # Builds production mode asset tags (from manifest)
      #
      # @param nonce [String] Content Security Policy nonce
      # @param entry [String] Vite manifest entry key to resolve (e.g. 'main.ts'
      #   or 'admin.ts'). Each entry is its own single chunk (codeSplitting:false).
      # @return [String] HTML tags for production assets
      def build_prod_assets(nonce, entry = 'main.ts')
        # Each entry is built in its own single-input Vite pass and writes its
        # own self-contained manifest (chunk + CSS + fonts). Resolve the file
        # for the requested entry: the admin console has manifest-admin.json,
        # everything else uses the default manifest.json.
        manifest_file = entry == 'admin.ts' ? 'manifest-admin.json' : 'manifest.json'
        manifest_path = File.join(PUBLIC_DIR, 'dist', '.vite', manifest_file)

        unless File.exist?(manifest_path)
          app_logger.error 'Vite manifest not found - frontend assets unavailable',
            {
              manifest_path: manifest_path,
              instruction: 'Run `pnpm run build` to generate assets',
            }
          return error_script(nonce, "Vite #{manifest_file} not found. Run `pnpm run build`")
        end

        @manifest_caches      ||= {}
        manifest                = (@manifest_caches[manifest_file] ||= Familia::JsonSerializer.parse(File.read(manifest_path)))
        entry_data              = manifest[entry]
        style_entry             = manifest['style.css'] # may not exist

        return error_script(nonce, "Entry '#{entry}' not found in Vite manifest") unless entry_data

        assets = []
        assets << build_script_tag(entry_data['file'], nonce)

        # Handle CSS attached to this entry's chunk
        if entry_data['css']&.any?
          entry_data['css'].each do |css_file|
            assets << build_css_tag(css_file, nonce)
          end
        end

        # Handle separate style.css entry. With cssCodeSplit:false the whole
        # build emits one stylesheet; depending on which entry it attaches to in
        # the manifest, this shared lookup guarantees the shell still links it.
        if style_entry && style_entry['file']
          assets << build_css_tag(style_entry['file'], nonce)
        end

        assets.concat(build_font_preloads(manifest, nonce))
        assets.join("\n")
      end

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

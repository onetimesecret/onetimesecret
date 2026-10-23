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
    # complexities of CSS bundling, font preloading and the CSP nonce model of a
    # code-split build.
    #
    # CSP nonce model. The production script-src is nonce-only (otto's
    # production_directives), and exactly one <script type="module"> per shell
    # has the nonce. The chunks that script imports, statically or via
    # import(), need no nonce of their own: the HTML spec defines a script's
    # cryptographic nonce as "The cryptographic nonce metadata used for the
    # initial fetch and for fetching any imported modules", and CSP's script
    # pre-request check allows a request whose nonce metadata matches the policy.
    # Two things do NOT inherit the nonce, and a blocked one breaks the page
    # (the browser then refuses the later import of the same URL, and the entry
    # reloads the page on vite:preloadError, at most once a minute; see
    # src/utils/preloadError.ts):
    #
    # - <link rel="modulepreload"> tags: each is its own fetch. The ones this
    #   helper emits for the entry's static imports get the nonce.
    # - The <link> tags Vite's preload helper creates before a dynamic import:
    #   it reads the nonce from <meta property="csp-nonce" nonce="..."> (vite 8,
    #   the preload() helper in importAnalysisBuild), so this helper emits that
    #   tag ahead of the entry script.
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
      #   or 'admin.ts'). Both entries are built in one pass and share chunks.
      # @return [String] HTML tags for production assets
      def build_prod_assets(nonce, entry = 'main.ts')
        manifest_path = File.join(PUBLIC_DIR, 'dist', '.vite', 'manifest.json')

        unless File.exist?(manifest_path)
          app_logger.error 'Vite manifest not found - frontend assets unavailable',
            {
              manifest_path: manifest_path,
              instruction: 'Run `pnpm run build` to generate assets',
            }
          return error_script(nonce, 'Vite manifest.json not found. Run `pnpm run build`')
        end

        @manifest_cache ||= Familia::JsonSerializer.parse(File.read(manifest_path))
        manifest          = @manifest_cache
        entry_data        = manifest[entry]
        style_entry       = manifest['style.css'] # may not exist

        return error_script(nonce, "Entry '#{entry}' not found in Vite manifest") unless entry_data

        assets = []
        assets << build_csp_nonce_meta(nonce)
        assets << build_script_tag(entry_data['file'], nonce)

        # The entry's static imports, transitively. The browser would discover
        # them anyway, one level per round trip as each chunk is parsed;
        # preloading fetches them all at once. These links need the nonce (see
        # the module comment).
        imported_chunk_files(manifest, entry).each do |file|
          assets << build_modulepreload_tag(file, nonce)
        end

        # The stylesheet. With cssCodeSplit:false the whole build emits one,
        # exposed under the manifest's `style.css` key; a chunk's own `css`
        # list is included for completeness and deduplicated against it.
        [*Array(entry_data['css']), style_entry&.dig('file')].compact.uniq.each do |css_file|
          assets << build_css_tag(css_file, nonce)
        end

        assets.concat(build_font_preloads(manifest, nonce))
        assets.join("\n")
      end

      # Static imports of a manifest entry, transitively and without
      # duplicates, as dist-relative file paths. Dynamic imports are left to
      # Vite's preload helper at runtime.
      #
      # @param manifest [Hash] Vite manifest data
      # @param key [String] Manifest key of the chunk to start from
      # @param seen [Hash] Keys already visited (shared across the recursion)
      # @return [Array<String>] Chunk file paths in preload order
      def imported_chunk_files(manifest, key, seen = {})
        Array(manifest.dig(key, 'imports')).flat_map do |dep|
          next [] if seen[dep]

          seen[dep] = true
          [manifest.dig(dep, 'file'), *imported_chunk_files(manifest, dep, seen)]
        end.compact
      end

      # Builds the meta tag Vite's preload helper reads the nonce from, for the
      # <link> tags it creates before a dynamic import. Without it those links
      # are blocked by the nonce-only script-src and every lazy route fails.
      #
      # @param nonce [String] Content Security Policy nonce
      # @return [String] HTML meta tag
      def build_csp_nonce_meta(nonce)
        %(<meta property="csp-nonce" nonce="#{nonce}">)
      end

      # Builds a script tag for JavaScript assets.
      #
      # @param file [String] Asset file path
      # @param nonce [String] Content Security Policy nonce
      # @return [String] HTML script tag
      def build_script_tag(file, nonce)
        %(<script type="module" nonce="#{nonce}" src="/dist/#{file}"></script>)
      end

      # Builds a modulepreload link for a chunk the entry imports statically.
      #
      # @param file [String] Chunk file path
      # @param nonce [String] Content Security Policy nonce
      # @return [String] HTML link tag
      def build_modulepreload_tag(file, nonce)
        %(    <link rel="modulepreload" nonce="#{nonce}" href="/dist/#{file}">)
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
      # `message` is developer/config-derived today (a manifest path or a hardcoded
      # entry name), so this is hardening of an unreachable path, not a live XSS fix.
      # Still, don't interpolate a bare string into a <script>: JSON-encode it for a
      # well-formed JS string literal, then neutralize any "</" so an embedded
      # "</script>" can't close the tag during HTML tokenization. (escape_html is the
      # WRONG tool here — HTML entities are not decoded inside <script>.)
      #
      # @param nonce [String] Content Security Policy nonce
      # @param message [String] Error message
      # @return [String] HTML script tag with error message
      def error_script(nonce, message)
        js = message.to_json.gsub('</', '<\/')
        %(<script nonce="#{nonce}">console.warn(#{js})</script>)
      end
    end
  end
end

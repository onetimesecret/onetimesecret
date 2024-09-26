# frozen_string_literal: true

module Onetime
  module App
    module Views
      module ViewHelpers # rubocop:disable Style/Documentation
        include Onetime::Logic::LogicHelpers

        def add_shrimp
          format('<input type="hidden" name="shrimp" value="%s" />', sess.add_shrimp)
        end

        def jsvar(name, value)
          value = case value.class.to_s
                  when 'String', 'Gibbler::Digest', 'Symbol', 'Integer', 'Float'
                    "'#{Rack::Utils.escape_html(value)}'"
                  when 'Array', 'Hash'
                    value.to_json
                  when 'NilClass'
                    'null'
                  when 'Boolean', 'FalseClass', 'TrueClass'
                    value
                  else
                    "console.error('#{value.class} is an unhandled type (named #{name})')"
                  end
          { name: name, value: value }
        end

        def cached_method methname
          rediskey = "template:global:#{methname}"
          cache_object = Familia::String.new rediskey, ttl: 1.hour, db: 0
          OT.ld "[cached_method] #{methname} #{cache_object.exists? ? 'hit' : 'miss'} #{rediskey}"
          cached = cache_object.get
          return cached if cached

          # Existing logic to generate assets...
          content = yield

          # Cache the generated content
          cache_object.set(content)

          content
        end

        def vite_assets
          cached_method :vite_assets do
            manifest_path = File.join(PUBLIC_DIR, 'dist', '.vite', 'manifest.json')
            unless File.exist?(manifest_path)
              OT.le "Vite manifest not found at #{manifest_path}. Run `pnpm run build`"
              return '<script>console.warn("Vite manifest not found. Run `pnpm run build`")</script>'
            end

            manifest = JSON.parse(File.read(manifest_path))

            assets = []

            # Add CSS files directly referenced in the manifest
            css_files = manifest.values.select { |v| v['file'].end_with?('.css') }
            assets << css_files.map do |css|
              %(<link rel="stylesheet" href="/dist/#{css['file']}">)
            end

            # Add CSS files referenced in the 'css' key of manifest entries
            css_linked_files = manifest.values.flat_map { |v| v['css'] || [] }
            assets << css_linked_files.map do |css_file|
              %(<link rel="stylesheet" href="/dist/#{css_file}">)
            end

            # Add JS files
            js_files = manifest.values.select { |v| v['file'].end_with?('.js') }
            assets << js_files.map do |js|
              %(<script type="module" src="/dist/#{js['file']}"></script>)
            end

            # Add preload directives for imported modules
            import_files = manifest.values.flat_map { |v| v['imports'] || [] }.uniq
            preload_links = import_files.map do |import_file|
              %(<link rel="modulepreload" href="/dist/#{manifest[import_file]['file']}">)
            end
            assets << preload_links

            if assets.empty?
              OT.le "No assets found in Vite manifest at #{manifest_path}"
              return '<script>console.warn("No assets found in Vite manifest")</script>'
            end

            assets.flatten.compact.join("\n")
          end
        end

      end
    end
  end
end

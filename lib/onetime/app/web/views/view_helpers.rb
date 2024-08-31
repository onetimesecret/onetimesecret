# frozen_string_literal: true

module Onetime
  class App
    module Views
      module ViewHelpers # rubocop:disable Style/Documentation

        def add_shrimp
          format('<input type="hidden" name="shrimp" value="%s" />', sess.add_shrimp)
        end

        def private_uri(obj)
          format('/private/%s', obj.key)
        end

        def secret_uri(obj)
          format('/secret/%s', obj.key)
        end

        def secret_display_domain(obj)
          scheme = base_scheme
          host = obj.share_domain || Onetime.conf[:site][:host]
          [scheme, host].join
        end

        def base_scheme
          Onetime.conf[:site][:ssl] ? 'https://' : 'http://'
        end

        def baseotsuri
          scheme = base_scheme
          [scheme, Onetime.conf[:site][:host]].join
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

        def server_port
          (defined?(req) ? req.env['SERVER_PORT'] : 443).to_i
        end

        def site_host
          Onetime.conf[:site][:host]
        end

        def baseuri
          scheme = base_scheme
          host = Onetime.conf[:site][:host]
          [scheme, host].join
        end

        def gravatar(email)
          return '/img/stella.png' if email.nil? || email.empty?

          suffix = Digest::MD5.hexdigest email.to_s.downcase
          prefix = secure_request? ? 'https://secure' : 'http://www'
          [prefix, '.gravatar.com/avatar/', suffix].join
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

        def secure_request?
          !local? || secure?
        end

        # TODO: secure ad local are already in Otto
        def secure?
          # X-Scheme is set by nginx
          # X-FORWARDED-PROTO is set by elastic load balancer
          req.env['HTTP_X_FORWARDED_PROTO'] == 'https' || req.env['HTTP_X_SCHEME'] == 'https'
        end

        def local?
          LOCAL_HOSTS.member?(req.env['SERVER_NAME']) && (req.client_ipaddress == '127.0.0.1')
        end

        protected

        def epochdate(time_in_s)
          time_parsed = Time.at time_in_s.to_i
          dformat time_parsed.utc
        end

        def epochtime(time_in_s)
          time_parsed = Time.at time_in_s.to_i
          tformat time_parsed.utc
        end

        def epochformat(time_in_s)
          time_parsed = Time.at time_in_s.to_i
          dtformat time_parsed.utc
        end

        def epochformat2(time_in_s)
          time_parsed = Time.at time_in_s.to_i
          dtformat2 time_parsed.utc
        end

        def epochdom(time_in_s)
          time_parsed = Time.at time_in_s.to_i
          time_parsed.utc.strftime('%b %d, %Y')
        end

        def epochtod(time_in_s)
          time_parsed = Time.at time_in_s.to_i
          time_parsed.utc.strftime('%I:%M%p').gsub(/^0/, '').downcase
        end

        def epochcsvformat(time_in_s)
          time_parsed = Time.at time_in_s.to_i
          time_parsed.utc.strftime('%Y/%m/%d %H:%M:%S')
        end

        def dtformat(time_in_s)
          time_in_s = DateTime.parse time_in_s unless time_in_s.is_a?(Time)
          time_in_s.strftime('%Y-%m-%d@%H:%M:%S UTC')
        end

        def dtformat2(time_in_s)
          time_in_s = DateTime.parse time_in_s unless time_in_s.is_a?(Time)
          time_in_s.strftime('%Y-%m-%d@%H:%M UTC')
        end

        def dformat(time_in_s)
          time_in_s = DateTime.parse time_in_s unless time_in_s.is_a?(Time)
          time_in_s.strftime('%Y-%m-%d')
        end

        def tformat(time_in_s)
          time_in_s = DateTime.parse time_in_s unless time_in_s.is_a?(Time)
          time_in_s.strftime('%H:%M:%S')
        end

        # rubocop:disable Metrics/PerceivedComplexity, Metrics/AbcSize
        def natural_time(time_in_s)
          return if time_in_s.nil?

          val = Time.now.utc.to_i - time_in_s.to_i
          # puts val
          if val < 10
            result = 'a moment ago'
          elsif val < 40
            result = "about #{(val * 1.5).to_i.to_s.slice(0, 1)}0 seconds ago"
          elsif val < 60
            result = 'about a minute ago'
          elsif val < 60 * 1.3
            result = '1 minute ago'
          elsif val < 60 * 2
            result = '2 minutes ago'
          elsif val < 60 * 50
            result = "#{(val / 60).to_i} minutes ago"
          elsif val < 3600 * 1.4
            result = 'about 1 hour ago'
          elsif val < 3600 * (24 / 1.02)
            result = "about #{(val / 60 / 60 * 1.02).to_i} hours ago"
          elsif val < 3600 * 24 * 1.6
            result = Time.at(time_in_s.to_i).strftime('yesterday').downcase
          elsif val < 3600 * 24 * 7
            result = Time.at(time_in_s.to_i).strftime('on %A').downcase
          else
            weeks = (val / 3600.0 / 24.0 / 7).to_i
            result = Time.at(time_in_s.to_i).strftime("#{weeks} #{'week'.plural(weeks)} ago").downcase
          end
          result
        end
        # rubocop:enable Metrics/PerceivedComplexity, Metrics/AbcSize
      end
    end
  end
end

# frozen_string_literal: true

module Onetime
  class App
    module Views
      module Helpers # rubocop:disable Style/Documentation
        attr_accessor :subdomain

        def add_shrimp
          format('<input type="hidden" name="shrimp" value="%s" />', sess.add_shrimp)
        end

        def private_uri(obj)
          format('/private/%s', obj.key)
        end

        def secret_uri(obj)
          format('/secret/%s', obj.key)
        end

        def baseotsuri
          scheme = Onetime.conf[:site][:ssl] ? 'https://' : 'http://'
          [scheme, Onetime.conf[:site][:host]].join
        end

        def jsvar(name, value)
          value = case value.class.to_s
                  when 'String', 'Gibbler::Digest', 'Symbol'
                    "'#{Rack::Utils.escape_html(value)}'"
                  when 'Array'
                    value.inspect
                  when 'Hash'
                    "jQuery.parseJSON('#{value.to_json}')"
                  when 'NilClass'
                    'null'
                  else
                    value
                  end
          { name: name, value: value }
        end

        def server_port
          (defined?(req) ? req.env['SERVER_PORT'] : 443).to_i
        end

        def current_subdomain
          defined?(req) ? req.env['ots.subdomain'] : subdomain
        end

        def baseuri
          scheme = Onetime.conf[:site][:ssl] ? 'https://' : 'http://'
          fulldomain = if current_subdomain
                         [current_subdomain['cname'], Onetime.conf[:site][:domain]].join('.')
                       else
                         Onetime.conf[:site][:host]
                       end
          [scheme, fulldomain].join
        end

        def gravatar(email)
          return '/img/stella.png' if email.nil? || email.empty?

          suffix = Digest::MD5.hexdigest email.to_s.downcase
          prefix = secure_request? ? 'https://secure' : 'http://www'
          [prefix, '.gravatar.com/avatar/', suffix].join
        end

        def vite_assets
          manifest_path = File.join(PUBLIC_DIR, 'dist', '.vite', 'manifest.json')
          return '' unless File.exist?(manifest_path)

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

          assets.flatten.compact.join("\n")
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

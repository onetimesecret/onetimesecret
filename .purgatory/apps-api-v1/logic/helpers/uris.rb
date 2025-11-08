# .purgatory/apps-api-v1/logic/helpers/uris.rb
#
# frozen_string_literal: true

require 'v1/utils'

module V1
  module Logic
    module UriHelpers
      include V1::TimeUtils

      def private_uri(obj)
        format('/private/%s', obj.key)
      end

      def secret_uri(obj)
        format('/secret/%s', obj.key)
      end

      def base_scheme
        Onetime.conf['site']['ssl'] ? 'https://' : 'http://'
      end

      def server_port
        (defined?(req) ? req.env['SERVER_PORT'] : 443).to_i
      end

      def site_host
        Onetime.conf['site']['host']
      end

      def baseuri
        scheme = base_scheme
        host = Onetime.conf['site']['host']
        [scheme, host].join
      end

      def build_path(*components)
        components.join('/')
      end

      def build_url(domain, path)
        [domain, path].flatten.join('/')
      end

    end
  end
end

# apps/api/v2/logic/helpers/uris.rb

require 'onetime/utils'

module V2
  module Logic
    module UriHelpers
      include Onetime::Utils::TimeUtils

      def receipt_uri(obj)
        format('/receipt/%s', obj.key)
      end
      alias private_uri receipt_uri

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
        host   = Onetime.conf['site']['host']
        [scheme, host].join
      end

      def build_path(*components)
        components.join('/')
      end

      def build_url(domain, path)
        [domain, path].flatten.join('/')
      end

      # TODO: secure ad local are already in Otto
      def secure?
        req.secure?
      end

      def local?
        req.local?
      end

      # Extract IP address from session for logging purposes
      def session_ipaddress
        sess&.[]('ip_address') || sess&.[](:ip_address) || 'unknown'
      end
    end
  end
end

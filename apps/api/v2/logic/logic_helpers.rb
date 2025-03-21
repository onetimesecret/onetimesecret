
module Onetime
  module Logic
    module LogicHelpers
      include Onetime::TimeUtils

      def private_uri(obj)
        format('/private/%s', obj.key)
      end

      def secret_uri(obj)
        format('/secret/%s', obj.key)
      end

      def base_scheme
        Onetime.conf[:site][:ssl] ? 'https://' : 'http://'
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

      def build_path(*components)
        components.join('/')
      end

      def build_url(domain, path)
        [domain, path].flatten.join('/')
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

    end
  end
end

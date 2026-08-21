# apps/api/colonel/auth_strategies.rb
#
# frozen_string_literal: true

require 'otto/utils'

module ColonelAPI
  module AuthStrategies
    include Onetime::Application::AuthStrategies

    class SessionAuthStrategy < Onetime::Application::AuthStrategies::SessionAuthStrategy
      @auth_method_name = 'sessionauth'

      PROXY_HEADERS_DEBUG_PATH = '/system/proxy-headers'

      CADDY_SNAPSHOT_HEADERS = %w[
        HTTP_X_OTS_PROXY_DEBUG_PEER
        HTTP_X_OTS_PROXY_DEBUG_HOST
        HTTP_X_OTS_PROXY_DEBUG_RECEIVED_X_FORWARDED_FOR
        HTTP_X_OTS_PROXY_DEBUG_RECEIVED_FORWARDED
        HTTP_X_OTS_PROXY_DEBUG_RECEIVED_APX_INCOMING_HOST
      ].freeze

      REQUEST_HEADERS = %w[
        HTTP_HOST
        HTTP_X_FORWARDED_FOR
        HTTP_X_FORWARDED_HOST
        HTTP_X_FORWARDED_PROTO
        HTTP_FORWARDED
        HTTP_APX_INCOMING_HOST
      ].freeze

      protected

      # Capture a fixed, non-sensitive subset only for the diagnostic route.
      # Its `network=admin` requirement makes both admin allowlists mandatory;
      # no request headers are added to ordinary Colonel strategy metadata.
      def build_metadata(env, additional = {})
        metadata = super
        return metadata unless Otto::Utils.normalize_path(env['PATH_INFO']) == PROXY_HEADERS_DEBUG_PATH

        metadata.merge(
          proxy_header_debug: {
            caddy_received: header_values(env, CADDY_SNAPSHOT_HEADERS),
            rack: {
              remote_addr: env['REMOTE_ADDR'],
              client_ip: env['otto.client_ip'],
              via_trusted_proxy: env['otto.via_trusted_proxy'],
              detected_host: env[Rack::DetectHost.result_field_name],
            },
            request_headers: header_values(env, REQUEST_HEADERS),
          },
        )
      end

      def header_values(env, keys)
        keys.to_h do |key|
          [key.delete_prefix('HTTP_').tr('_', '-').downcase, env[key]]
        end
      end
    end

    def self.register_essential(router)
      # Register the colonel-specific authentication strategies
      router.add_auth_strategy('noauth', Onetime::Application::AuthStrategies::NoAuthStrategy.new)
      router.add_auth_strategy('sessionauth', SessionAuthStrategy.new)

      # HTTP Basic Auth - also auto-registers devbasicauth when DEV_BASIC_AUTH=true
      Onetime::Application::AuthStrategies.register_basic_auth(router)
    end
  end
end

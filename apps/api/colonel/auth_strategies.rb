# apps/api/colonel/auth_strategies.rb
#
# frozen_string_literal: true

require 'otto/utils'

module ColonelAPI
  module AuthStrategies
    include Onetime::Application::AuthStrategies

    class SessionAuthStrategy < Onetime::Application::AuthStrategies::SessionAuthStrategy
      @auth_method_name = 'sessionauth'

      # Colonel diagnostic endpoint. The only route where build_metadata attaches
      # proxy headers (see: docs/operations/proxy-header-diagnostic.md).
      PROXY_DEBUG_HEADERS_PATH = '/system/proxy-headers'

      # `X-OTS-Proxy-Debug-*`: what the reverse proxy saw, injected by Caddy's
      # `(onetime-proxy-debug)` snippet (a path-matched `route` of
      # `request_header` directives) on PROXY_DEBUG_HEADERS_PATH only.
      PROXY_DEBUG_HEADERS = %w[
        HTTP_X_OTS_PROXY_DEBUG_PEER
        HTTP_X_OTS_PROXY_DEBUG_CLIENT_IP
        HTTP_X_OTS_PROXY_DEBUG_HOST
        HTTP_X_OTS_PROXY_DEBUG_RECEIVED_X_FORWARDED_FOR
        HTTP_X_OTS_PROXY_DEBUG_RECEIVED_X_FORWARDED_HOST
        HTTP_X_OTS_PROXY_DEBUG_RECEIVED_X_REAL_IP
        HTTP_X_OTS_PROXY_DEBUG_RECEIVED_X_CLIENT_IP
        HTTP_X_OTS_PROXY_DEBUG_RECEIVED_FORWARDED
        HTTP_X_OTS_PROXY_DEBUG_RECEIVED_APX_INCOMING_HOST
      ].freeze

      # Forwarding headers as this strategy sees them, for comparison against
      # PROXY_DEBUG_HEADERS and the resolved env values. Two of these —
      # X-Forwarded-Host and Forwarded — are deleted by
      # Onetime::Middleware::StripForwardedHost before any app runs, so they
      # read nil here whenever the edge sent them; the middleware records the
      # names it deleted in STRIPPED_FORWARDED_HEADERS, reported alongside so
      # "nil because absent" and "nil because stripped" stay distinguishable.
      FORWARDING_HEADERS = %w[
        HTTP_HOST
        HTTP_X_FORWARDED_FOR
        HTTP_X_FORWARDED_HOST
        HTTP_X_FORWARDED_PROTO
        HTTP_X_REAL_IP
        HTTP_X_CLIENT_IP
        HTTP_FORWARDED
        HTTP_APX_INCOMING_HOST
      ].freeze

      # Env key StripForwardedHost leaves the names of the carriers it deleted
      # in (names only, never values). Literal rather than the middleware's
      # constant so this strategy does not load the middleware.
      STRIPPED_FORWARDED_HEADERS = 'onetime.stripped_forwarded_headers'

      # Destructive-action confirmation token (#4326). Carried as a REQUEST HEADER,
      # never a query parameter: the tokens are frequently PII (a target's email,
      # an org display name) and a query string is logged verbatim by every default
      # access-log format, lands in browser history, and can leak via Referer.
      CONFIRM_HEADER = 'HTTP_X_OTS_CONFIRM'

      # DoS ceiling on the ENCODED header, not a token-length limit: the real cap
      # is MAX_CONFIRM_LENGTH (characters, post-decode) in the logic layer. It is
      # measured on the encoded bytes, which percent-encoding expands up to 12 per
      # 4-byte codepoint, so a max-length (255-char) token can approach 3 KB
      # encoded. An over-long header is REJECTED, never truncated: slicing the
      # encoded bytes would sever a %XX escape or a multibyte character and turn a
      # valid token — e.g. a 100-char CJK org display_name, ~900 bytes encoded —
      # into a permanent 403. 4 KB clears the largest legitimate token with room
      # to spare while still bounding the decode.
      MAX_CONFIRM_BYTES = 4096

      protected

      # Capture a fixed, non-sensitive subset only for the diagnostic route.
      # Its `network=admin` requirement makes both admin allowlists mandatory;
      # no request headers are added to ordinary Colonel strategy metadata.
      #
      # The confirmation token and the request method are the TWO exceptions:
      # both are merged on EVERY colonel request, before the diagnostic branch's
      # early exit, because they are how the logic layer receives them (logic
      # classes never see the Rack env). The method is what lets
      # ColonelAPI::Logic::Base tell a mutation from a read and charge the broad
      # colonel:mutation bucket accordingly (#4329) — neither value is a request
      # header echo, and neither is sensitive.
      def build_metadata(env, additional = {})
        colonel_context = {
          confirm_token: confirm_token_from(env),
          request_method: env['REQUEST_METHOD'],
        }
        metadata        = super(env, additional.merge(colonel_context))
        return metadata unless Otto::Utils.normalize_path(env['PATH_INFO']) == PROXY_DEBUG_HEADERS_PATH

        metadata.merge(
          proxy_header_debug: {
            caddy_received: header_values(env, PROXY_DEBUG_HEADERS),
            rack: {
              remote_addr: env['REMOTE_ADDR'],
              client_ip: env['otto.client_ip'],
              via_trusted_proxy: env['otto.via_trusted_proxy'],
              detected_host: env[Rack::DetectHost.result_field_name],
              stripped_forwarded_headers: header_names(env[STRIPPED_FORWARDED_HEADERS]),
            },
            request_headers: header_values(env, FORWARDING_HEADERS),
          },
        )
      end

      def header_values(env, keys)
        keys.to_h do |key|
          [header_name(key), env[key]]
        end
      end

      def header_names(keys)
        Array(keys).map { |key| header_name(key) }
      end

      # Rack env key -> wire header name: HTTP_X_FORWARDED_FOR -> x-forwarded-for
      def header_name(key)
        key.delete_prefix('HTTP_').tr('_', '-').downcase
      end

      # Percent-decoded so a non-ASCII token (org display names) survives the
      # ISO-8859-1 header charset both sides agree on. An absent, empty, oversized
      # or undecodable header is "no token" — never a crash, never a partial match.
      #
      # FORM decoding (Rack::Utils.unescape), which accepts the widest range of
      # correct encodings for a token that routinely contains SPACES (org
      # display_names): the console's encodeURIComponent ('%20'), a raw space, AND
      # form-encoding ('+') from curl / Rack::Utils.escape / a Ruby client. A
      # component decoder that kept '+' literal would 403 every form-encoded
      # space — i.e. most DeleteOrganization / AddMembership / entitlement calls
      # from a non-browser client. The one cost is that a raw, UNENCODED literal
      # '+' decodes to a space; clients that mean a literal '+' encode it '%2B'
      # (encodeURIComponent and every form encoder both do), which round-trips.
      # Oversized headers are rejected whole (see MAX_CONFIRM_BYTES) rather than
      # sliced, so a legitimate multibyte token is never severed mid-escape.
      def confirm_token_from(env)
        raw = env[CONFIRM_HEADER].to_s
        return nil if raw.empty?
        return nil if raw.bytesize > MAX_CONFIRM_BYTES

        Rack::Utils.unescape(raw, Encoding::UTF_8)
      rescue StandardError
        nil
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

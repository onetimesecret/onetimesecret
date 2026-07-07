# lib/onetime/application/middleware_stack.rb
#
# frozen_string_literal: true

require 'rack/content_length'
require 'rack/contrib'
require 'rack/parser'
require 'rack/protection'
require 'rack/utf8_sanitizer'

require_relative '../session'
require_relative '../middleware/ip_ban'
require_relative '../middleware/health_access_control'
require_relative '../middleware/admin_network_isolation'
require_relative '../middleware/csrf_response_header'
require_relative '../middleware/normalize_content_type'
require 'otto'

module Onetime
  module Application
    # MiddlewareStack - Universal Rack Middleware Configuration
    #
    # Provides common middleware configuration shared across ALL Rack applications
    # in the Onetime ecosystem, regardless of routing framework.
    #
    # ## Architecture Principles
    #
    # This module contains ONLY middleware that is:
    # - Framework-agnostic (works with Otto, Roda, or any Rack app)
    # - Security-critical (CSRF, sessions, IP privacy)
    # - Infrastructure-level (logging, monitoring, error tracking)
    #
    # ## What Does NOT Belong Here
    #
    # Router-specific configuration (Otto hooks, Roda plugins) belongs in
    # the individual application classes:
    # - `apps/web/core/application.rb` - Otto-based web app
    # - `apps/api/v2/application.rb` - Otto-based API
    # - `apps/web/auth/application.rb` - Roda-based authentication
    #
    # For Otto-specific hooks, see `Onetime::Application::OttoHooks`
    #
    # ## Application Initialization Flow
    #
    # 1. Application class inherits from `Onetime::Application::Base`
    # 2. `Base#initialize` calls `build_rack_app`
    # 3. `build_rack_app` calls `MiddlewareStack.configure` (universal middleware)
    # 4. Application-specific middleware added via class-level `use` calls
    # 5. `build_router` creates router instance (Otto/Roda/etc)
    # 6. Router-specific configuration happens in `build_router`
    #
    module MiddlewareStack
      @parsers = {
        'application/json' => proc { |body| Familia::JsonSerializer.parse(body) },
        'application/x-www-form-urlencoded' => proc { |body| Rack::Utils.parse_nested_query(body) },
      }.freeze

      # IP ranges that are always treated as proxy hops, never as the client.
      # IPv4: RFC1918 (10/8, 172.16/12, 192.168/16), loopback (127/8) and
      # link-local (169.254/16). IPv6: loopback (::1), ULA (fc00::/7, the
      # f[cd] branch) and link-local (fe80::/10, the fe[89ab] branch). Otto's
      # IPPrivacyMiddleware walks X-Forwarded-For and returns the first
      # address that does NOT match a trusted proxy, so trusting these private
      # ranges is what lets the real public visitor IP surface in deployments
      # where every proxy hop has an internal address (Kubernetes ingress,
      # cloud load balancers).
      #
      # Consumed only by ip_privacy_security_config below, which feeds it to
      # Otto::Security::Config#add_trusted_proxy as the default trusted-proxy
      # set (operator-configured site.network.trusted_proxy.cidrs are appended).
      # Kept at module scope so it stays lexically visible to the singleton
      # methods in `class << self` below.
      PRIVATE_PROXY_RANGES = /
        \A(?:
          10\.|
          127\.|
          192\.168\.|
          169\.254\.|
          172\.(?:1[6-9]|2\d|3[01])\.|
          ::1\z|
          f[cd]|
          fe[89ab]
        )
      /ix

      class << self
        # Build locale map for Otto::Locale::Middleware
        #
        # Creates a hash mapping locale codes to language names for all
        # supported locales. Uses English locale file names as the source.
        #
        # @return [Hash<String, String>] Locale code to language name mapping
        def build_available_locales
          # Map of locale codes to language names
          # This could be loaded from locale files in the future
          locale_names = {
            'ar' => 'العربية',
            'bg' => 'Български',
            'ca_ES' => 'Català',
            'cs' => 'Čeština',
            'da_DK' => 'Dansk',
            'de' => 'Deutsch',
            'de_AT' => 'Deutsch (Österreich)',
            'el_GR' => 'Ελληνικά',
            'en' => 'English',
            'eo' => 'Esperanto',
            'es' => 'Español',
            'fr_CA' => 'Français (Canada)',
            'fr_FR' => 'Français (France)',
            'he' => 'עברית',
            'hu' => 'Magyar',
            'it_IT' => 'Italiano',
            'ja' => '日本語',
            'ko' => '한국어',
            'mi_NZ' => 'Te Reo Māori',
            'nl' => 'Nederlands',
            'pl' => 'Polski',
            'pt_BR' => 'Português (Brasil)',
            'pt_PT' => 'Português (Portugal)',
            'ru' => 'Русский',
            'sl_SI' => 'Slovenščina',
            'sv_SE' => 'Svenska',
            'tr' => 'Türkçe',
            'uk' => 'Українська',
            'vi' => 'Tiếng Việt',
            'zh' => '中文',
          }

          # Build locale map from supported locales, adding primary
          # language code entries for regional variants. This ensures
          # that when Otto::Locale::Middleware extracts "it" from
          # Accept-Language "it-IT", it finds a valid locale even
          # though the canonical code is "it_IT".
          locales = {}
          OT.supported_locales.each do |locale|
            locales[locale] = locale_names.fetch(locale, locale)

            # Add primary language code fallback (e.g. "it" for "it_IT")
            # only if no locale with that primary code is already present
            primary            = locale.split('_').first
            locales[primary] ||= locales[locale] unless locales.key?(primary)
          end
          locales
        end

        # Normalize fallback_locale config keys from BCP 47 hyphens (fr-CA)
        # to POSIX underscores (fr_CA) that Otto expects. Values are already
        # in underscore format.
        def normalize_fallback_keys(raw)
          return nil unless raw.is_a?(Hash) && !raw.empty?

          raw.each_with_object({}) do |(key, chain), normalized|
            normalized[key.to_s.tr('-', '_')] = chain
          end
        end

        # Build the Otto security config handed to IPPrivacyMiddleware.
        #
        # This is the SINGLE source of truth that translates the YAML
        # site.network.trusted_proxy block into an Otto::Security::Config. Otto
        # 2.3.0 hosts all client-IP / trusted-proxy resolution (CIDR-walk and
        # count-based depth), so Onetime no longer carries a parallel
        # ConfigureTrustedProxy Rack monkeypatch or a ClientIpHelpers depth
        # walker — this method is the whole of the translation.
        #
        # Returns nil when trusted proxy support is disabled, which leaves the
        # middleware in its default direct-connection mode (REMOTE_ADDR is the
        # client) — correct for deployments not behind a proxy.
        #
        # The returned config also enables full IP masking (mask_private_ips)
        # so the single universal IPPrivacyMiddleware mount masks private/
        # localhost addresses too — the behavior the per-router
        # enable_full_ip_privacy! calls used to provide before they were
        # removed in favor of one mount.
        #
        # Modes (site.network.trusted_proxy.mode):
        #   - filter (default): CIDR-walk. Trusts the RFC1918/loopback/link-local
        #     PRIVATE_PROXY_RANGES regex PLUS every entry in `cidrs` (real IPAddr
        #     CIDR containment via add_trusted_proxy). Otto::Utils.resolve_client_ip
        #     walks the forwarded chain and returns the first non-proxy hop.
        #   - depth: count-based. Trusts the last N hops. Onetime depth N maps to
        #     otto trusted_proxy_depth = N + 1 because otto's chain appends
        #     REMOTE_ADDR (one hop longer than Onetime's XFF-only chain). See the
        #     otto v2.3.0 migration guide. Mutually exclusive with add_trusted_proxy.
        #
        # Header (site.network.trusted_proxy.header): in depth mode otto 2.3.1
        # counts hops from the configured forwarded header — 'X-Forwarded-For'
        # (default), RFC 7239 'Forwarded', or 'Both' — wired straight through to
        # Otto::Security::Config#trusted_proxy_header (otto#150). The setter
        # validates the value and raises on a typo, so a bad header fails the
        # boot loudly rather than silently resolving from the wrong source. In
        # filter/CIDR-walk mode otto reads the X-Forwarded-For family only and
        # ignores this setting — matching the original ClientIpHelpers, where
        # `header` was likewise a depth-mode-only concept.
        #
        # Always returns a config (never nil): when no proxy is declared it
        # carries mask_private_ips with an empty trust list, so private/localhost
        # masking still applies to direct-connect deployments.
        #
        # @return [Otto::Security::Config]
        def ip_privacy_security_config
          config = Otto::Security::Config.new

          # Mask private/localhost IPs too, always. With one universal mount this
          # is what the removed router-level enable_full_ip_privacy! calls
          # provided — and those ran unconditionally, so masking must hold even
          # for direct-connect deployments that declare no reverse proxy.
          # Otherwise RFC1918/localhost client addresses would leak unmasked into
          # session metadata, rate-limit keys, and logs.
          config.ip_privacy_config.mask_private_ips = true

          # No declared reverse proxy means no hop to trust: leave the proxy list
          # empty so the middleware resolves the client from REMOTE_ADDR (and
          # still masks it per the flag above).
          return config unless trusted_proxy_enabled?

          tp     = OT.conf.dig('site', 'network', 'trusted_proxy') || {}
          mode   = tp['mode'] || 'filter'
          header = tp['header'].to_s.strip
          header = 'X-Forwarded-For' if header.empty?

          # Which forwarded header depth mode counts hops from (otto#150). otto
          # honors this in depth mode only and reads the X-Forwarded-For family
          # in CIDR-walk; the setter canonicalizes and raises on an unrecognized
          # value, so a typo fails the boot rather than silently mis-resolving.
          config.trusted_proxy_header = header

          if mode == 'depth'
            ots_depth                  = tp['depth'].to_i.clamp(1, 10)
            # otto#151 remap: otto's chain is XFF + [REMOTE_ADDR], one hop longer
            # than Onetime's XFF-only chain, so resolve the same client by
            # trusting one extra hop. Mutually exclusive with add_trusted_proxy —
            # do NOT also register CIDRs (otto raises).
            config.trusted_proxy_depth = ots_depth + 1
          else
            # filter / CIDR-walk: trust the private proxy ranges plus any
            # operator-configured public CIDRs (e.g. a CDN's egress ranges).
            config.add_trusted_proxy(PRIVATE_PROXY_RANGES)
            Array(tp['cidrs']).each do |cidr|
              next if cidr.to_s.strip.empty?

              config.add_trusted_proxy(cidr.to_s.strip)
            end
          end

          config
        end

        # Whether the deployment has declared a trusted reverse proxy in front
        # of the app (site.network.trusted_proxy.enabled). Gate for the single
        # IP-resolution path: the universal IPPrivacyMiddleware mount, configured
        # from ip_privacy_security_config (above). There is no longer a separate
        # Otto-router trust list or Rack monkeypatch to keep in agreement —
        # otto 2.3.0 resolves the client IP once into env['otto.client_ip'].
        #
        # @return [Boolean]
        def trusted_proxy_enabled?
          OT.conf.dig('site', 'network', 'trusted_proxy', 'enabled') == true
        end

        def configure(builder, application_context: nil)
          logger = Onetime.get_logger('App')
          logger.debug 'Configuring common middleware',
            {
              application: application_context&.[](:name),
            }

          # IP Privacy FIRST - masks public IPs before logging/monitoring
          # Private/localhost IPs are automatically exempted for development
          # Uses Otto's privacy middleware as a standalone Rack component.
          #
          # The middleware needs a security config that knows which proxies to
          # trust; without one it treats REMOTE_ADDR (the ingress/proxy hop) as
          # the client and overwrites X-Forwarded-For with it, hiding the real
          # visitor IP from every downstream consumer (ban checks, sessions,
          # identity resolution, the Colonel "current IP" panel). See
          # ip_privacy_security_config.
          ip_privacy_config = ip_privacy_security_config
          logger.debug 'Setting up IP Privacy middleware',
            {
              note: 'masks public and private IPs',
              trusted_proxy: trusted_proxy_enabled?,
            }
          builder.use Otto::Security::Middleware::IPPrivacyMiddleware, ip_privacy_config

          # IPPrivacyMiddleware scrubs these headers by assigning nil ("even if
          # nil, to clear original sensitive data"), leaving a present-but-nil
          # CGI key. That violates the Rack spec (CGI keys must be Strings) and
          # trips Rack::Lint in development (Core::Middleware::ViteProxy). Drop
          # the scrubbed keys so an absent header reads as never-sent. (otto
          # should delete rather than nil; until it does, we clean up here.)
          builder.use Rack::Config do |env|
            %w[HTTP_REFERER HTTP_USER_AGENT].each { |k| env.delete(k) if env[k].nil? }
          end

          # IP Ban middleware - blocks banned IPs (after IP privacy)
          logger.debug 'Setting up IP Ban middleware'
          builder.use Onetime::Middleware::IPBan

          # Health endpoint access control - restrict to localhost/private networks
          logger.debug 'Setting up Health Access Control middleware'
          builder.use Onetime::Middleware::HealthAccessControl

          # Admin network isolation - optional CIDR allowlist for the Colonel
          # surfaces (/colonel + /api/colonel). No-op unless
          # site.admin.allowed_cidrs is configured; then a request from outside
          # the allowlist gets a 404 (indistinguishable-from-absent). Runs after
          # IP privacy so it can use the trusted-proxy-resolved client IP.
          logger.debug 'Setting up Admin Network Isolation middleware'
          builder.use Onetime::Middleware::AdminNetworkIsolation

          builder.use Rack::ContentLength
          builder.use Onetime::Middleware::StartupReadiness

          # Host detection and identity resolution (common to all apps)
          builder.use Rack::DetectHost, logger: Onetime.http_logger

          # Adds env['HTTP_X_REQUEST_ID']
          require 'middleware/request_id'
          builder.use Rack::RequestId, generator: -> { Familia.generate_trace_id }

          # Recover a parseable Content-Type for clients that send malformed
          # or duplicate Content-Type headers (e.g. legacy PHP clients that
          # set text/html before application/x-www-form-urlencoded). See
          # Onetime::Middleware::NormalizeContentType for the rationale.
          builder.use Onetime::Middleware::NormalizeContentType
          builder.use Rack::Parser, parsers: @parsers
          # Add session middleware early in the stack (before other middleware)
          session_config = Onetime.session_config

          builder.use Onetime::Session,
            {
              secret: session_config['secret'],
              expire_after: session_config['expire_after'],
              key: session_config['key'],
              secure: session_config['secure'],
              same_site: session_config['same_site'].to_sym,
            }

          # Identity resolution middleware (after session)
          builder.use Onetime::Middleware::IdentityResolution

          # Locale detection middleware (after session, before domain strategy)
          # Sets env['otto.locale'] based on URL param, session, Accept-Language header.
          # Otto 2.0 handles exact region matching (fr-FR → fr_FR) and fallback
          # chains natively via the fallback_locale option.
          logger.debug 'Setting up Locale detection middleware'
          available_locales = build_available_locales
          fallback_locale   = normalize_fallback_keys(OT.fallback_locale)
          builder.use Otto::Locale::Middleware,
            available_locales: available_locales,
            default_locale: OT.default_locale,
            fallback_locale: fallback_locale,
            debug: OT.debug?

          # I18n locale middleware (after Otto locale detection)
          # Sets I18n.locale for the request using env['otto.locale']
          require 'middleware/i18n_locale'
          builder.use ::Middleware::I18nLocale

          # Domain strategy middleware (after identity)
          builder.use Onetime::Middleware::DomainStrategy, application_context: application_context

          # Load the logger early so it's ready to log request errors
          # Only add middleware if HTTP logging config exists and is enabled
          http_logging_conf = Onetime.logging_conf&.dig('http')
          if http_logging_conf && http_logging_conf['enabled'] != false
            logger.debug 'Setting up RequestLogger middleware'
            builder.use Onetime::Application::RequestLogger, http_logging_conf
          end

          # Error Monitoring Integration
          # Add Sentry exception tracking when available
          # This block only executes if Sentry was successfully initialized
          Onetime.with_diagnostics do |diagnostics_conf|
            logger.debug 'Sentry enabled',
              {
                config: diagnostics_conf,
              }
            # Position Sentry middleware early to capture exceptions throughout the stack
            builder.use Sentry::Rack::CaptureExceptions
          end

          # CSRF Response Header - MUST be before Security middleware so that
          # 403 responses from AuthenticityToken also get a fresh masked token.
          logger.debug 'Setting up CSRF Response Header middleware'
          builder.use Onetime::Middleware::CsrfResponseHeader

          # Security Middleware Configuration
          # Configures security-related middleware components based on application settings
          logger.debug 'Setting up Security middleware'
          builder.use Onetime::Middleware::Security
        end
      end
    end
  end
end
